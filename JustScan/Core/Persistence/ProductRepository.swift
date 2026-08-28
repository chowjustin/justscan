//
//  ProductRepository.swift
//  JustScan
//
//  Fetch, insert, save. No rules, no validation, no decisions — those live in
//  the service that calls this (CONVENTIONS.md, layering).
//
//  Uniqueness is enforced here rather than in the schema, because CloudKit does
//  not support unique constraints (ADR-02, D-10). `findBy(barcode:)` runs inside
//  `CatalogueService.create`, never in a ViewModel (R-03-2).
//

import Foundation
import SwiftData

protocol ProductRepository {
    /// Non-deleted product carrying this barcode, or nil. Soft-deleted rows are
    /// invisible here, which is what scopes uniqueness to live rows (R-03-1).
    func findBy(barcode: String) throws -> Product?

    /// Non-deleted product with this identifier, or nil.
    ///
    /// A stale reference — a row that was never inserted, or one soft-deleted
    /// since it was handed out — reads as absent here. That is what lets a
    /// service fail loudly with `productNotFound` instead of writing to a dead
    /// row (R-03-14).
    func find(id: UUID) throws -> Product?

    /// All non-deleted products, name-ascending.
    func all() throws -> [Product]

    /// Stage an insert. Not committed until `save()`.
    func insert(_ product: Product)

    /// Commit. Exactly one call per business operation (CONVENTIONS.md).
    ///
    /// `save()` lives on this repository alone, and the repositories share one
    /// `ModelContext` — so a single call here commits movements staged through
    /// `StockMovementRepository` in the same operation. Putting it in one place
    /// is what makes "one save per business operation" structurally obvious
    /// rather than a rule someone has to remember (R-03-11, R-04-15).
    func save() throws
}

struct SwiftDataProductRepository: ProductRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func findBy(barcode: String) throws -> Product? {
        // Filtered in memory rather than by predicate: foundations §8 sizes the
        // catalogue at 200–2,000 products and explicitly sanctions this.
        try all().first { $0.barcode == barcode }
    }

    func find(id: UUID) throws -> Product? {
        // Same in-memory filter as `findBy(barcode:)`, and sanctioned by the
        // same sizing note in foundations §8.
        try all().first { $0.id == id }
    }

    func all() throws -> [Product] {
        let descriptor = FetchDescriptor<Product>(
            sortBy: [SortDescriptor(\Product.name, order: .forward)]
        )
        return try context.fetch(descriptor).filter { $0.deletedAt == nil }
    }

    func insert(_ product: Product) {
        context.insert(product)
    }

    func save() throws {
        try context.save()
    }
}

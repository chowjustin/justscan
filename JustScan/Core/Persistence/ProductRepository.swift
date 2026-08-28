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

    /// Product with this identifier **whether or not it is soft-deleted**.
    ///
    /// The one read that deliberately sees dead rows. Module 04 needs it: a
    /// sale of a product that was soft-deleted mid-cart still records its
    /// movement against that product's ledger, and so does the void that
    /// reverses it (04 §8). Every other caller wants `find(id:)`.
    func findAny(id: UUID) throws -> Product?

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

    /// Discard everything staged since the last `save()`.
    ///
    /// Lives beside `save()` for the same reason, and is called on exactly one
    /// path: a business operation whose commit threw. Without it the failed
    /// operation's inserts stay in the shared context and ride along on the
    /// next successful save — a second attempt at a tender would commit the
    /// first attempt's sale too (04 §8, AC-04-16).
    func rollback()
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

    func findAny(id: UUID) throws -> Product? {
        // Not routed through `all()`: this is the one read that must see rows
        // `all()` filters out.
        let descriptor = FetchDescriptor<Product>(
            sortBy: [SortDescriptor(\Product.name, order: .forward)]
        )
        return try context.fetch(descriptor).first { $0.id == id }
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

    func rollback() {
        context.rollback()
    }
}

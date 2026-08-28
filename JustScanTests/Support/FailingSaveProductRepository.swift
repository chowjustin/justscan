//
//  FailingSaveProductRepository.swift
//  JustScanTests
//
//  A real `SwiftDataProductRepository` with one thing changed: `save()` throws.
//
//  AC-04-16 asks what a forced failure inside `complete` leaves behind, and the
//  honest answer needs a real store — `InMemoryProductRepository` has no store
//  to observe, so it can prove the error and the save count but not that zero
//  rows were written. This decorator keeps every read and every insert going to
//  a genuine `ModelContext`, so a second context can be asked what landed.
//

import Foundation
import SwiftData
@testable import JustScan

final class FailingSaveProductRepository: ProductRepository, @unchecked Sendable {
    /// Thrown by `save()` when set. Nil lets the save through.
    var saveError: Error?

    private(set) var saveCount = 0
    private(set) var rollbackCount = 0

    private let wrapped: ProductRepository

    init(wrapping wrapped: ProductRepository, saveError: Error? = nil) {
        self.wrapped = wrapped
        self.saveError = saveError
    }

    func findBy(barcode: String) throws -> Product? { try wrapped.findBy(barcode: barcode) }
    func find(id: UUID) throws -> Product? { try wrapped.find(id: id) }
    func findAny(id: UUID) throws -> Product? { try wrapped.findAny(id: id) }
    func all() throws -> [Product] { try wrapped.all() }
    func insert(_ product: Product) { wrapped.insert(product) }

    func save() throws {
        saveCount += 1
        if let saveError { throw saveError }
        try wrapped.save()
    }

    func rollback() {
        rollbackCount += 1
        wrapped.rollback()
    }
}

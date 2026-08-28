//
//  InMemoryProductRepository.swift
//  JustScanTests
//
//  A `ProductRepository` with no store behind it, so a test can make `save()`
//  fail on demand. Foundations §7 requires a service to wrap a repository
//  throw in `.persistenceFailed`, and an in-memory SwiftData container has no
//  way to be asked to fail.
//
//  Everything else in this module is tested against a real container
//  (03 §13.9); this fake exists for the failure path alone.
//

import Foundation
@testable import JustScan

final class InMemoryProductRepository: ProductRepository, @unchecked Sendable {
    /// Thrown by `save()` when set. Nil means the save succeeds.
    var saveError: Error?

    private(set) var stored: [Product] = []
    private(set) var saveCount = 0
    private(set) var rollbackCount = 0

    init(stored: [Product] = []) {
        self.stored = stored
    }

    func findBy(barcode: String) throws -> Product? {
        try all().first { $0.barcode == barcode }
    }

    func find(id: UUID) throws -> Product? {
        try all().first { $0.id == id }
    }

    func findAny(id: UUID) throws -> Product? {
        stored.first { $0.id == id }
    }

    func all() throws -> [Product] {
        stored
            .filter { $0.deletedAt == nil }
            .sorted { $0.name < $1.name }
    }

    func insert(_ product: Product) {
        stored.append(product)
    }

    func save() throws {
        saveCount += 1
        if let saveError { throw saveError }
    }

    func rollback() {
        rollbackCount += 1
    }
}

//
//  StockService.swift
//  JustScan
//
//  The only place in this app that writes `Product.stockQty` (R-03-6).
//
//  It lives in Core/ rather than Features/Catalogue/ because module 04 records
//  a movement on every sale and every void — two features depend on it, which
//  is the actual test for what belongs in Core (STRUCTURE.md).
//
//  The ledger is the truth; `stockQty` is a cache of it. Every method that
//  changes a quantity inserts its movement and updates the cache inside one
//  `save()` (R-03-11) — a movement without its cache update, or a cache update
//  without its movement, is the worst bug this module can produce.
//

import Foundation
import OSLog

protocol StockServicing {
    func record(product: Product, delta: Int,
                reason: StockReason, note: String?, saleID: UUID?) throws
    func adjust(product: Product, countedQty: Int, note: String) throws
    func recompute(product: Product) throws -> Int     // returns new qty
    func movements(for product: Product) throws -> [StockMovement]  // newest first
}

struct StockService: StockServicing {
    private static let log = Logger(subsystem: "chow.JustScan", category: "stock")

    private let products: ProductRepository
    private let ledger: StockMovementRepository

    init(products: ProductRepository, movements: StockMovementRepository) {
        self.products = products
        self.ledger = movements
    }

    /// Appends one movement and moves the cache by the same amount.
    ///
    /// `delta` is never zero: recording a no-op pollutes a ledger whose whole
    /// job is to explain a quantity (03 §8, R-03-13). The cache is **never**
    /// clamped — a negative result means goods left the shelf that the ledger
    /// did not know about, which is information (R-03-7).
    func record(product: Product, delta: Int,
                reason: StockReason, note: String?, saleID: UUID?) throws {
        try requireLive(product)

        guard delta != 0 else { throw POSError.validationFailed(field: "qty") }
        guard reason.requiresSaleID == (saleID != nil) else {
            throw POSError.validationFailed(field: "reason")
        }

        let movement = StockMovement(
            product: product,
            delta: delta,
            reason: reason,
            note: note,
            saleID: saleID
        )

        ledger.insert(movement)
        product.stockQty += delta

        // One save for the whole operation, committing the movement and the
        // cache together (R-03-11).
        try commit()

        Self.log.info("""
            movement \(movement.id, privacy: .public) \
            \(reason.rawValue, privacy: .public) \(delta, privacy: .public) \
            product \(product.id, privacy: .public) → \(product.stockQty, privacy: .public)
            """)
    }

    /// Sets stock to a **counted** quantity, not a delta (03 §3).
    ///
    /// The operator counts what is on the shelf; the arithmetic is this
    /// service's job. Counting the same number twice writes nothing.
    func adjust(product: Product, countedQty: Int, note: String) throws {
        try requireLive(product)

        // You cannot count a negative number of items off a shelf. Negative
        // stock is still reachable — through `record` — which is where a sale
        // of goods the ledger did not know about lands (R-03-7).
        guard countedQty >= 0 else { throw POSError.validationFailed(field: "qty") }

        let reason = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { throw POSError.validationFailed(field: "reason") }

        let delta = countedQty - product.stockQty
        // Nothing changed, so nothing is written and nothing is saved (03 §8).
        guard delta != 0 else { return }

        try record(product: product, delta: delta, reason: .adjustment,
                   note: reason, saleID: nil)
    }

    /// Rebuilds the cache from the ledger and returns the result.
    ///
    /// If the returned value differs from the `stockQty` the caller saw, that
    /// is a cache bug and the caller surfaces it — this method never hides one
    /// (03 §3).
    func recompute(product: Product) throws -> Int {
        try requireLive(product)

        let total = try movements(for: product).reduce(0) { $0 + $1.delta }
        product.stockQty = total
        try commit()

        Self.log.info("""
            recompute product \(product.id, privacy: .public) \
            → \(total, privacy: .public)
            """)
        return total
    }

    /// Read-only, so a soft-deleted product is still legible here: 03 §8 keeps
    /// its movements "for audit", which is unreadable if the only reader
    /// refuses. R-03-14 guards the four methods that *write*.
    func movements(for product: Product) throws -> [StockMovement] {
        do {
            return try ledger.movements(for: product)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }

    /// R-03-14. A reference to a product that was never inserted, or has been
    /// soft-deleted since it was handed out, fails loudly rather than writing
    /// to a dead row.
    private func requireLive(_ product: Product) throws {
        guard product.deletedAt == nil else { throw POSError.productNotFound }

        let live: Product?
        do {
            live = try products.find(id: product.id)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
        guard live != nil else { throw POSError.productNotFound }
    }

    /// Never `try?` on a write path — a swallowed save failure is a lost sale
    /// (CONVENTIONS.md).
    private func commit() throws {
        do {
            try products.save()
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }
}

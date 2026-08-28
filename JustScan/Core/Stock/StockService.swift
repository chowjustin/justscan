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

    /// `record` without the commit, stamped with a caller-supplied instant.
    ///
    /// Exists for module 04 alone. `SaleService.complete` has to put the sale,
    /// its lines, and every movement in **one** `save()` (R-04-15); calling
    /// `record` per line would save per line, and a failure on line two would
    /// leave line one's movement committed — the partial write that rule
    /// exists to prevent. The caller commits, exactly once.
    ///
    /// `createdAt` is a parameter for the same reason: a tender captures one
    /// instant and reuses it for the number, the sale, and every movement
    /// (04 §8, CONVENTIONS.md §Time).
    ///
    /// Unlike the four committing methods it tolerates a **soft-deleted**
    /// product: a sale of goods deleted mid-cart, and the void that reverses
    /// it, both still belong on that product's ledger (04 §8). It still
    /// refuses a product that was never inserted.
    func stage(product: Product, delta: Int, reason: StockReason,
               note: String?, saleID: UUID?, at createdAt: Date) throws
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

    /// Appends one movement, moves the cache by the same amount, and commits.
    func record(product: Product, delta: Int,
                reason: StockReason, note: String?, saleID: UUID?) throws {
        try requireLive(product)
        // One save for the whole operation, committing the movement and the
        // cache together (R-03-11).
        try append(product: product, delta: delta, reason: reason,
                   note: note, saleID: saleID, at: Date())
        try commit()
    }

    /// See the protocol. Everything `record` does except the commit, and with
    /// the liveness check relaxed to mere existence (04 §8).
    func stage(product: Product, delta: Int, reason: StockReason,
               note: String?, saleID: UUID?, at createdAt: Date) throws {
        try requireExists(product)
        try append(product: product, delta: delta, reason: reason,
                   note: note, saleID: saleID, at: createdAt)
    }

    /// The shared body: validate, append one movement, move the cache by the
    /// same amount. Never commits — its two callers decide that.
    ///
    /// `delta` is never zero: recording a no-op pollutes a ledger whose whole
    /// job is to explain a quantity (03 §8, R-03-13). The cache is **never**
    /// clamped — a negative result means goods left the shelf that the ledger
    /// did not know about, which is information (R-03-7).
    private func append(product: Product, delta: Int, reason: StockReason,
                        note: String?, saleID: UUID?, at createdAt: Date) throws {
        guard delta != 0 else { throw POSError.validationFailed(field: "qty") }
        guard reason.requiresSaleID == (saleID != nil) else {
            throw POSError.validationFailed(field: "reason")
        }

        let movement = StockMovement(
            product: product,
            delta: delta,
            reason: reason,
            note: note,
            saleID: saleID,
            createdAt: createdAt
        )

        ledger.insert(movement)
        product.stockQty += delta

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
    /// to a dead row. Guards the four **catalogue-facing** writers.
    private func requireLive(_ product: Product) throws {
        guard product.deletedAt == nil else { throw POSError.productNotFound }
        try requireExists(product)
    }

    /// The weaker half of R-03-14, for `stage`.
    ///
    /// A soft-deleted product is a legitimate target here: 04 §8 states twice
    /// that a sale of goods deleted mid-cart, and the void reversing it, both
    /// land on that product's ledger — "correct and harmless". What stays
    /// forbidden is a row that does not exist at all, which is a stale
    /// reference and a bug.
    private func requireExists(_ product: Product) throws {
        let known: Product?
        do {
            known = try products.findAny(id: product.id)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
        guard known != nil else { throw POSError.productNotFound }
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

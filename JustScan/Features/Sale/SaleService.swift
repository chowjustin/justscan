//
//  SaleService.swift
//  JustScan
//
//  Tender and void. Every rule in 04 §4 lives here, and the two write methods
//  are each **one** `save()` (R-04-15).
//
//  That single commit is the point of this file. A sale persisted without its
//  stock movements — or reversed money without reversed stock — is the worst
//  bug this system can produce, so the movements are *staged* through
//  `StockServicing.stage` and committed together with the sale, rather than
//  each committing itself. If the commit throws, the whole operation is rolled
//  back and nothing at all was written (AC-04-16).
//
//  This service never writes `stockQty`. `StockServicing` is the only path to
//  a quantity, in this module as in every other (R-03-6, AC-04-17).
//

import Foundation
import OSLog

protocol SaleServicing {
    func complete(lines: [DraftLine],
                  method: PaymentMethod,
                  cashReceivedRp: Int?,
                  customer: ContactRef?) throws -> Sale
    func void(_ sale: Sale, reason: String) throws
    func sales(onJakartaDay day: Date) throws -> [Sale]
    func allSales(limit: Int, offset: Int) throws -> [Sale]   // newest first
}

struct SaleService: SaleServicing {
    private static let log = Logger(subsystem: "chow.JustScan", category: "sale")

    private let repository: SaleRepository
    private let products: ProductRepository
    private let stock: StockServicing

    /// `products` is here for two reasons and no others: resolving a
    /// `DraftLine.productID` to the row its movement attaches to, and owning
    /// the single `save()`/`rollback()` pair for the whole operation.
    init(sales: SaleRepository, products: ProductRepository, stock: StockServicing) {
        self.repository = sales
        self.products = products
        self.stock = stock
    }

    // MARK: - Tender

    /// The pivot event. One transaction: number, sale, lines, movements, save
    /// (04 §3).
    ///
    /// Stock is never consulted. Insufficient stock does not block a sale and
    /// never has — a shop that cannot sell what is already in the customer's
    /// hand is broken, so the quantity simply goes negative and the ledger says
    /// so (R-04-6, D-05).
    func complete(lines: [DraftLine],
                  method: PaymentMethod,
                  cashReceivedRp: Int?,
                  customer: ContactRef?) throws -> Sale {
        guard !lines.isEmpty else { throw POSError.emptyCart }        // R-04-7

        // R-04-16. Unreachable from the cart, which removes a line rather than
        // holding one at zero; reaching it means a draft was built by hand.
        guard lines.allSatisfy({ $0.qty >= 1 }) else {
            throw POSError.validationFailed(field: "qty")
        }

        let totalRp = lines.reduce(0) { $0 + $1.lineTotalRp }          // R-04-5
        let payment = try Self.settle(method: method,
                                      cashReceivedRp: cashReceivedRp,
                                      totalRp: totalRp)

        // Resolved before anything is staged, so a stale line fails the tender
        // before it has written a thing.
        var resolved: [(line: DraftLine, product: Product)] = []
        for line in lines {
            resolved.append((line, try product(for: line.productID)))
        }

        // One instant for the number, the sale, and every movement. A tender at
        // 23:59:58 whose commit lands at 00:00:01 stays on one Jakarta day,
        // with a number and a grouping that agree (04 §8).
        let createdAt = Date()

        let sale = Sale(
            number: try allocateNumber(at: createdAt),                 // R-04-4
            totalRp: totalRp,
            method: method,
            cashReceivedRp: payment.cashReceivedRp,
            changeRp: payment.changeRp,
            status: .completed,
            createdAt: createdAt
        )
        sale.customer = customer          // R-02-5: both columns move together
        repository.insert(sale)

        do {
            for (line, product) in resolved {
                // R-04-3. The snapshot is the whole point: a later price edit,
                // or a soft delete, must never reach back into a closed sale.
                let saleLine = SaleLine(
                    sale: sale,
                    productID: line.productID,
                    nameSnapshot: line.name,
                    unitPriceRp: line.unitPriceRp,
                    qty: line.qty,
                    lineTotalRp: line.lineTotalRp                       // R-04-5
                )
                repository.insert(saleLine)

                try stock.stage(product: product, delta: -line.qty,
                                reason: .sale, note: nil, saleID: sale.id,
                                at: createdAt)
            }

            try commit()                                               // R-04-15
        } catch {
            try rollback(after: error)
        }

        Self.log.info("""
            sale \(sale.id, privacy: .public) \(sale.number, privacy: .public) \
            \(method.rawValue, privacy: .public) total \(totalRp, privacy: .public) \
            lines \(lines.count, privacy: .public) completed
            """)
        return sale
    }

    // MARK: - Void

    /// Reverses money and stock together, or neither (R-04-13). Writes new
    /// rows; edits none, deletes none (D-06).
    ///
    /// The number is retained. A gap in a receipt sequence is indistinguishable
    /// from a hidden sale, so a voided sale keeps its number and still consumes
    /// it (R-04-4, D-17).
    func void(_ sale: Sale, reason: String) throws {
        guard sale.status != .voided else { throw POSError.saleAlreadyVoided }  // R-04-12

        // R-04-14. A void with no reason is a void nobody can explain later.
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...120).contains(cleanReason.count) else {
            throw POSError.validationFailed(field: "reason")
        }

        let lines = sale.lines ?? []
        var resolved: [(line: SaleLine, product: Product)] = []
        for line in lines {
            resolved.append((line, try product(for: line.productID)))
        }

        let voidedAt = Date()
        sale.statusRaw = SaleStatus.voided.rawValue
        sale.voidedAt = voidedAt
        sale.voidReason = cleanReason

        do {
            for (line, product) in resolved {
                // Exactly one `+qty` movement per original line, carrying the
                // same saleID, so the ledger reads as a pair (R-04-13).
                try stock.stage(product: product, delta: line.qty,
                                reason: .void, note: cleanReason, saleID: sale.id,
                                at: voidedAt)
            }

            try commit()                                               // R-04-15
        } catch {
            try rollback(after: error)
        }

        Self.log.info("""
            sale \(sale.id, privacy: .public) \(sale.number, privacy: .public) \
            voided, \(lines.count, privacy: .public) lines reversed
            """)
    }

    // MARK: - Reads (module 05)

    func sales(onJakartaDay day: Date) throws -> [Sale] {
        do {
            return try repository.sales(onJakartaDay: day)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }

    func allSales(limit: Int, offset: Int) throws -> [Sale] {
        do {
            return try repository.all(limit: limit, offset: offset)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }

    // MARK: - Rules

    /// R-04-8 and R-04-10, the whole of the money branch.
    ///
    /// `nil` and `0` are not interchangeable here and never will be: nil means
    /// "not applicable", zero means "no change was due". Conflating them
    /// corrupts every report built on top (D-08).
    private static func settle(method: PaymentMethod,
                               cashReceivedRp: Int?,
                               totalRp: Int) throws -> (cashReceivedRp: Int?, changeRp: Int?) {
        switch method {
        case .qris:
            // QRIS is exact by construction. Anything the caller passed is
            // discarded rather than stored as a number that means nothing.
            return (nil, nil)

        case .cash:
            // No cash entered is not a free sale — it is the whole total still
            // owed.
            let received = cashReceivedRp ?? 0
            let shortfall = totalRp - received
            guard shortfall <= 0 else {
                throw POSError.insufficientCash(shortfallRp: shortfall)
            }
            // Exactly equal to the total gives 0, which is a real answer and
            // distinct from QRIS's nil (04 §8).
            return (received, received - totalRp)
        }
    }

    /// R-04-4. `{YYYYMMDD}-{NNN}` in Asia/Jakarta, allocated as the count of
    /// that Jakarta day's sales plus one.
    ///
    /// Voided sales are counted, which is what makes the sequence gapless: void
    /// `-007` and the next sale that day is still `-008` (04 §11, D-17).
    private func allocateNumber(at createdAt: Date) throws -> String {
        let existing: Int
        do {
            existing = try repository.countOfSales(onJakartaDay: createdAt)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
        return String(format: "%@-%03d", JakartaDay.key(createdAt), existing + 1)
    }

    /// The row a movement attaches to.
    ///
    /// `findAny` deliberately, not `find`: a product soft-deleted between the
    /// scan and the tender still owns the ledger the sale belongs on, and so
    /// does the void that reverses it (04 §8). A product that does not exist at
    /// all is a stale reference — money would move with no stock behind it, so
    /// it fails loudly and the tender writes nothing.
    private func product(for productID: UUID?) throws -> Product {
        guard let productID else { throw POSError.productNotFound }

        let found: Product?
        do {
            found = try products.findAny(id: productID)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
        guard let found else { throw POSError.productNotFound }
        return found
    }

    // MARK: - Persistence

    /// Never `try?` on a write path — a swallowed save failure is a lost sale
    /// (CONVENTIONS.md).
    private func commit() throws {
        do {
            try products.save()
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }

    /// Discards everything the failed operation staged and rethrows.
    ///
    /// Without this the sale, its lines, and the movements it already staged
    /// stay in the shared context and ride along on the next successful save —
    /// so a retried tender would commit the failed attempt too (AC-04-16).
    private func rollback(after error: Error) throws -> Never {
        products.rollback()
        throw error
    }
}

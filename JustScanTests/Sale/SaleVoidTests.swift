//
//  SaleVoidTests.swift
//  JustScanTests
//
//  R-04-11..14 — the reversal. Money and stock reverse together, or neither
//  does, and nothing is ever edited or deleted (D-06).
//
//  The §11 VOID worked example is reproduced with its exact numbers.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct SaleVoidTests {

    private func makeProduct(
        _ wiring: TestContainer.SaleWiring,
        name: String, priceRp: Int, stockQty: Int
    ) throws -> Product {
        let product = try wiring.catalogue.create(name: name, priceRp: priceRp,
                                                  barcode: nil, supplier: nil)
        try wiring.stock.record(product: product, delta: stockQty, reason: .restock,
                                note: nil, saleID: nil)
        return product
    }

    private func draft(_ product: Product, qty: Int) -> DraftLine {
        DraftLine(productID: product.id, name: product.name,
                  unitPriceRp: product.priceRp, qty: qty)
    }

    /// The §11 cart: Chitato ×2 at 12.000, Teh Botol ×1 at 5.000, total 29.000.
    private func workedExample(_ wiring: TestContainer.SaleWiring) throws
    -> (chitato: Product, tehBotol: Product, sale: Sale) {
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)
        let sale = try wiring.sales.complete(
            lines: [draft(chitato, qty: 2), draft(tehBotol, qty: 1)],
            method: .cash, cashReceivedRp: 50_000, customer: nil
        )
        return (chitato, tehBotol, sale)
    }

    // MARK: - AC-04-10 / R-04-13 — the reversal

    @Test("AC-04-10/R-04-13: void writes one +qty movement per line and restores every quantity")
    func test_AC0410_R0413_voidReversesMoneyAndStockTogether() throws {
        let wiring = try TestContainer.sale()
        let (chitato, tehBotol, sale) = try workedExample(wiring)

        // §11: Stock 24 → 22 and 12 → 11 after the sale.
        #expect(chitato.stockQty == 22)
        #expect(tehBotol.stockQty == 11)

        try wiring.sales.void(sale, reason: "salah barang")

        // §11: Stock 22 → 24 and 11 → 12 after the void.
        #expect(chitato.stockQty == 24)
        #expect(tehBotol.stockQty == 12)

        let chitatoVoids = try wiring.stock.movements(for: chitato).filter { $0.reason == .void }
        let tehBotolVoids = try wiring.stock.movements(for: tehBotol).filter { $0.reason == .void }
        #expect(chitatoVoids.count == 1)
        #expect(chitatoVoids[0].delta == 2)
        #expect(chitatoVoids[0].saleID == sale.id)
        #expect(tehBotolVoids.count == 1)
        #expect(tehBotolVoids[0].delta == 1)
        #expect(tehBotolVoids[0].saleID == sale.id)

        // §11: "Chitato ledger now reads: +24 restock, −2 sale, +2 void → 24."
        let ledger = try wiring.stock.movements(for: chitato)
        #expect(ledger.map(\.delta).reduce(0, +) == 24)
        #expect(Set(ledger.map(\.reason)) == [.restock, .sale, .void])
    }

    @Test("R-04-13/D-06: a void writes new rows and edits or deletes none")
    func test_R0413_voidIsAppendOnly() throws {
        let wiring = try TestContainer.sale()
        let (chitato, _, sale) = try workedExample(wiring)

        let before = try wiring.stock.movements(for: chitato)
        #expect(before.count == 2)                      // restock, sale
        let beforeIDs = Set(before.map(\.id))

        try wiring.sales.void(sale, reason: "salah barang")

        let after = try wiring.stock.movements(for: chitato)
        #expect(after.count == 3)
        // Every original movement is still there, unchanged.
        #expect(beforeIDs.isSubset(of: Set(after.map(\.id))))
        #expect(after.first { $0.reason == .sale }?.delta == -2)

        // The lines survive too — a void is not a delete.
        #expect(sale.lines?.count == 2)
        #expect(sale.totalRp == 29_000)
    }

    @Test("R-04-13/R-04-15: a void is one save, whatever the line count")
    func test_R0413_R0415_voidIsOneSave() throws {
        let wiring = try TestContainer.sale()
        let (_, _, sale) = try workedExample(wiring)

        let before = wiring.products.saveCount
        try wiring.sales.void(sale, reason: "salah barang")
        #expect(wiring.products.saveCount - before == 1)
        #expect(wiring.products.rollbackCount == 0)
    }

    // MARK: - R-04-4 / §11 — the number is retained

    @Test("R-04-4/D-17: a voided sale keeps its number and its total")
    func test_R0404_voidedSaleRetainsItsNumber() throws {
        let wiring = try TestContainer.sale()
        let (_, _, sale) = try workedExample(wiring)
        let number = sale.number

        try wiring.sales.void(sale, reason: "salah barang")

        #expect(sale.number == number)
        #expect(sale.totalRp == 29_000)
        #expect(sale.status == .voided)
        #expect(sale.voidedAt != nil)
        #expect(sale.voidReason == "salah barang")
    }

    // MARK: - AC-04-11 / R-04-12 — idempotence guard

    @Test("AC-04-11/R-04-12: voiding a voided sale throws saleAlreadyVoided and writes nothing")
    func test_AC0411_R0412_doubleVoidThrows() throws {
        let wiring = try TestContainer.sale()
        let (chitato, tehBotol, sale) = try workedExample(wiring)

        try wiring.sales.void(sale, reason: "salah barang")
        let firstVoidedAt = sale.voidedAt
        let savesAfterFirst = wiring.products.saveCount

        // 04 §8: a double tap, or the same sale open on two screens.
        #expect(throws: POSError.saleAlreadyVoided) {
            try wiring.sales.void(sale, reason: "salah lagi")
        }

        #expect(wiring.products.saveCount == savesAfterFirst)
        #expect(sale.voidedAt == firstVoidedAt)
        #expect(sale.voidReason == "salah barang")
        #expect(chitato.stockQty == 24)                 // not 26
        #expect(tehBotol.stockQty == 12)                // not 13

        let observer = ModelContext(wiring.container)
        let voids = try observer.fetch(FetchDescriptor<StockMovement>())
            .filter { $0.reason == .void }
        #expect(voids.count == 2)                       // one per line, still
    }

    // MARK: - AC-04-12 / R-04-14 — the reason

    @Test("AC-04-12/R-04-14: an empty reason throws validationFailed(field: \"reason\")")
    func test_AC0412_R0414_emptyReasonThrows() throws {
        let wiring = try TestContainer.sale()
        let (chitato, _, sale) = try workedExample(wiring)

        #expect(throws: POSError.validationFailed(field: "reason")) {
            try wiring.sales.void(sale, reason: "")
        }
        #expect(throws: POSError.validationFailed(field: "reason")) {
            try wiring.sales.void(sale, reason: "   \n  ")
        }

        #expect(sale.status == .completed)
        #expect(chitato.stockQty == 22)
    }

    @Test("R-04-14: the reason is trimmed and capped at 120 characters")
    func test_R0414_reasonIsTrimmedAndBounded() throws {
        let wiring = try TestContainer.sale()

        let padded = try workedExample(wiring)
        try wiring.sales.void(padded.sale, reason: "  salah barang  ")
        #expect(padded.sale.voidReason == "salah barang")

        let atLimit = try workedExample(wiring)
        let exactly120 = String(repeating: "a", count: 120)
        try wiring.sales.void(atLimit.sale, reason: exactly120)
        #expect(atLimit.sale.voidReason?.count == 120)

        let tooLong = try workedExample(wiring)
        #expect(throws: POSError.validationFailed(field: "reason")) {
            try wiring.sales.void(tooLong.sale, reason: String(repeating: "a", count: 121))
        }
        #expect(tooLong.sale.status == .completed)
    }

    // MARK: - 04 §8 edges

    @Test("04 §8: a void whose product was soft-deleted still reverses onto its ledger")
    func test_voidOfADeletedProductStillReverses() throws {
        let wiring = try TestContainer.sale()
        let (chitato, _, sale) = try workedExample(wiring)

        try wiring.catalogue.softDelete(chitato)
        try wiring.sales.void(sale, reason: "salah barang")

        #expect(chitato.stockQty == 24)
        #expect(try wiring.stock.movements(for: chitato).first?.reason == .void)
        #expect(sale.status == .voided)
    }

    @Test("R-04-11: nothing on SaleServicing can add, remove, or re-price a closed sale")
    func test_R0411_aCompletedSaleIsImmutableExceptForTheVoidFields() throws {
        let wiring = try TestContainer.sale()
        let (_, _, sale) = try workedExample(wiring)

        let snapshot = (number: sale.number, totalRp: sale.totalRp,
                        lineCount: sale.lines?.count ?? 0,
                        cash: sale.cashReceivedRp, change: sale.changeRp,
                        method: sale.method)

        try wiring.sales.void(sale, reason: "salah barang")

        // The void touched exactly three fields and nothing else.
        #expect(sale.number == snapshot.number)
        #expect(sale.totalRp == snapshot.totalRp)
        #expect(sale.lines?.count == snapshot.lineCount)
        #expect(sale.cashReceivedRp == snapshot.cash)
        #expect(sale.changeRp == snapshot.change)
        #expect(sale.method == snapshot.method)
    }
}

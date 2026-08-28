//
//  SaleServiceTests.swift
//  JustScanTests
//
//  R-04-3, R-04-5..8, R-04-10, R-04-15 — tender and the money.
//
//  AC-04-16 is written first and sits at the top of this file, exactly as
//  04 §13.10 asks. It is the one that protects the money: everything else here
//  is only trustworthy if a failed commit writes nothing at all.
//
//  The §11 worked examples are reproduced with their exact numbers.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct SaleServiceTests {

    // MARK: - Helpers

    /// A saved, live product to sell.
    private func makeProduct(
        _ wiring: TestContainer.SaleWiring,
        name: String,
        priceRp: Int,
        stockQty: Int = 0
    ) throws -> Product {
        let product = try wiring.catalogue.create(name: name, priceRp: priceRp,
                                                  barcode: nil, supplier: nil)
        if stockQty != 0 {
            try wiring.stock.record(product: product, delta: stockQty,
                                    reason: .opening, note: nil, saleID: nil)
        }
        return product
    }

    private func draft(_ product: Product, qty: Int) -> DraftLine {
        DraftLine(productID: product.id, name: product.name,
                  unitPriceRp: product.priceRp, qty: qty)
    }

    /// What a **separate** context onto the same store can see. The only
    /// honest way to ask "what was actually written".
    private func committed(_ wiring: TestContainer.SaleWiring) throws
    -> (sales: Int, lines: Int, movements: Int) {
        let observer = ModelContext(wiring.container)
        return (
            try observer.fetch(FetchDescriptor<Sale>()).count,
            try observer.fetch(FetchDescriptor<SaleLine>()).count,
            try observer.fetch(FetchDescriptor<StockMovement>()).count
        )
    }

    // MARK: - AC-04-16 — no partial write. Written first.

    @Test("AC-04-16/R-04-15: a forced failure inside complete writes zero sales, zero lines, zero movements")
    func test_AC0416_forcedFailureWritesNothing() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)

        // Two products, two opening movements, no sales — the baseline.
        let before = try committed(wiring)
        #expect(before.sales == 0)
        #expect(before.lines == 0)
        #expect(before.movements == 2)

        // The commit fails, and it is the *only* commit the operation makes.
        wiring.products.saveError = CocoaError(.fileWriteUnknown)
        let savesBefore = wiring.products.saveCount

        var thrown: POSError?
        do {
            _ = try wiring.sales.complete(
                lines: [draft(chitato, qty: 2), draft(tehBotol, qty: 1)],
                method: .cash, cashReceivedRp: 50_000, customer: nil
            )
        } catch let error as POSError {
            thrown = error
        }

        guard case .persistenceFailed = thrown else {
            Issue.record("expected persistenceFailed, got \(String(describing: thrown))")
            return
        }

        // R-04-15: one save attempt for the whole operation, not one per line.
        #expect(wiring.products.saveCount - savesBefore == 1)
        #expect(wiring.products.rollbackCount == 1)

        // AC-04-16: nothing landed. Not a sale, not a line, not a movement.
        let after = try committed(wiring)
        #expect(after.sales == 0)
        #expect(after.lines == 0)
        #expect(after.movements == 2)
    }

    @Test("AC-04-16: a retried tender after a failure commits one sale, not two")
    func test_AC0416_rollbackLeavesNothingToRideAlong() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        wiring.products.saveError = CocoaError(.fileWriteUnknown)
        #expect(throws: POSError.self) {
            _ = try wiring.sales.complete(lines: [self.draft(chitato, qty: 2)],
                                          method: .cash, cashReceivedRp: 50_000,
                                          customer: nil)
        }

        // The operator taps Bayar again and it works this time.
        wiring.products.saveError = nil
        let sale = try wiring.sales.complete(lines: [draft(chitato, qty: 2)],
                                             method: .cash, cashReceivedRp: 50_000,
                                             customer: nil)

        let after = try committed(wiring)
        #expect(after.sales == 1)
        #expect(after.lines == 1)
        // One opening plus one sale movement. The abandoned attempt left none.
        #expect(after.movements == 2)
        #expect(sale.number.hasSuffix("-001"))
        #expect(chitato.stockQty == 22)
    }

    @Test("R-04-15: a void that fails to commit reverses neither money nor stock")
    func test_R0415_voidFailureReversesNothing() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let sale = try wiring.sales.complete(lines: [draft(chitato, qty: 2)],
                                             method: .cash, cashReceivedRp: 50_000,
                                             customer: nil)
        #expect(chitato.stockQty == 22)

        wiring.products.saveError = CocoaError(.fileWriteUnknown)
        #expect(throws: POSError.self) {
            try wiring.sales.void(sale, reason: "salah barang")
        }

        // Money and stock reverse together or neither does (R-04-13).
        let observer = ModelContext(wiring.container)
        let stored = try observer.fetch(FetchDescriptor<Sale>()).first
        #expect(stored?.status == .completed)
        #expect(stored?.voidedAt == nil)
        #expect(try observer.fetch(FetchDescriptor<StockMovement>()).count == 2)
    }

    // MARK: - R-04-7 — empty cart

    @Test("AC-04-3/R-04-7: complete with zero lines throws emptyCart and persists nothing")
    func test_AC0403_R0407_emptyCartThrows() throws {
        let wiring = try TestContainer.sale()

        #expect(throws: POSError.emptyCart) {
            _ = try wiring.sales.complete(lines: [], method: .cash,
                                          cashReceivedRp: 50_000, customer: nil)
        }

        let after = try committed(wiring)
        #expect(after.sales == 0)
        #expect(after.lines == 0)
        #expect(after.movements == 0)
        // Nothing was staged, so nothing was saved either.
        #expect(wiring.products.saveCount == 0)
    }

    // MARK: - R-04-8 — cash

    @Test("AC-04-4/R-04-8: cash below total throws insufficientCash with the exact shortfall")
    func test_AC0404_R0408_insufficientCashCarriesTheShortfall() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)

        // §11 INSUFFICIENT CASH: total 29.000, received 25.000 → shortfall 4.000.
        #expect(throws: POSError.insufficientCash(shortfallRp: 4_000)) {
            _ = try wiring.sales.complete(
                lines: [self.draft(chitato, qty: 2), self.draft(tehBotol, qty: 1)],
                method: .cash, cashReceivedRp: 25_000, customer: nil
            )
        }

        let after = try committed(wiring)
        #expect(after.sales == 0)
        #expect(after.lines == 0)
        #expect(after.movements == 2)   // the two openings, untouched
    }

    @Test("AC-04-5/R-04-8: 29.000 tendered with 50.000 stores changeRp 21000")
    func test_AC0405_R0408_changeIsCashMinusTotal() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)

        // §11 SALE — CASH, exactly.
        let sale = try wiring.sales.complete(
            lines: [draft(chitato, qty: 2), draft(tehBotol, qty: 1)],
            method: .cash, cashReceivedRp: 50_000, customer: nil
        )

        #expect(sale.totalRp == 29_000)
        #expect(sale.method == .cash)
        #expect(sale.cashReceivedRp == 50_000)
        #expect(sale.changeRp == 21_000)
        #expect(sale.status == .completed)
        #expect(chitato.stockQty == 22)
        #expect(tehBotol.stockQty == 11)
    }

    @Test("R-04-8/04 §8: cash exactly equal to the total gives changeRp 0, not nil")
    func test_R0408_exactCashGivesZeroChangeNotNil() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        let sale = try wiring.sales.complete(lines: [draft(chitato, qty: 2)],
                                             method: .cash, cashReceivedRp: 24_000,
                                             customer: nil)

        #expect(sale.changeRp == 0)
        #expect(sale.changeRp != nil)
    }

    @Test("04 §8: a 1.000.000 overpay on a 29.000 sale is allowed, change 971.000")
    func test_overpayIsNotPoliced() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)

        let sale = try wiring.sales.complete(
            lines: [draft(chitato, qty: 2), draft(tehBotol, qty: 1)],
            method: .cash, cashReceivedRp: 1_000_000, customer: nil
        )
        #expect(sale.changeRp == 971_000)
    }

    @Test("R-04-8: cash with no amount entered is the whole total still owed")
    func test_R0408_cashWithNoAmountIsInsufficientByTheTotal() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        #expect(throws: POSError.insufficientCash(shortfallRp: 24_000)) {
            _ = try wiring.sales.complete(lines: [self.draft(chitato, qty: 2)],
                                          method: .cash, cashReceivedRp: nil,
                                          customer: nil)
        }
    }

    // MARK: - R-04-10 — QRIS

    @Test("AC-04-6/R-04-10: a QRIS sale stores nil for cash and change, never 0")
    func test_AC0406_R0410_qrisStoresNilNotZero() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)

        // §11 SALE — QRIS, same cart. "nil is not 0."
        let sale = try wiring.sales.complete(
            lines: [draft(chitato, qty: 2), draft(tehBotol, qty: 1)],
            method: .qris, cashReceivedRp: nil, customer: nil
        )

        #expect(sale.totalRp == 29_000)
        #expect(sale.method == .qris)
        #expect(sale.cashReceivedRp == nil)
        #expect(sale.changeRp == nil)
    }

    @Test("R-04-10: a cash amount passed with QRIS is discarded, not stored")
    func test_R0410_qrisDiscardsAnyCashAmount() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        let sale = try wiring.sales.complete(lines: [draft(chitato, qty: 1)],
                                             method: .qris, cashReceivedRp: 50_000,
                                             customer: nil)

        #expect(sale.cashReceivedRp == nil)
        #expect(sale.changeRp == nil)
    }

    // MARK: - R-04-5 — line totals and the stored sale total

    @Test("R-04-5: lineTotalRp is unitPrice × qty and totalRp is their stored sum")
    func test_R0405_totalsAreStoredNotComputed() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)

        let sale = try wiring.sales.complete(
            lines: [draft(chitato, qty: 2), draft(tehBotol, qty: 1)],
            method: .cash, cashReceivedRp: 29_000, customer: nil
        )

        let lines = (sale.lines ?? []).sorted { $0.lineTotalRp > $1.lineTotalRp }
        #expect(lines.count == 2)
        #expect(lines[0].unitPriceRp == 12_000)
        #expect(lines[0].qty == 2)
        #expect(lines[0].lineTotalRp == 24_000)
        #expect(lines[1].lineTotalRp == 5_000)
        #expect(sale.totalRp == 29_000)

        // Stored, not computed at read time — a second context reads the same
        // number without touching a line.
        let observer = ModelContext(wiring.container)
        #expect(try observer.fetch(FetchDescriptor<Sale>()).first?.totalRp == 29_000)
    }

    // MARK: - R-04-3 — snapshots

    @Test("AC-04-13/R-04-3: editing a product's price leaves the closed sale untouched")
    func test_AC0413_R0403_priceEditNeverReachesBackIntoASale() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        let sale = try wiring.sales.complete(lines: [draft(chitato, qty: 2)],
                                             method: .cash, cashReceivedRp: 50_000,
                                             customer: nil)
        #expect(sale.totalRp == 24_000)

        try wiring.catalogue.update(chitato, name: chitato.name,
                                    priceRp: 20_000, supplier: nil)

        #expect(chitato.priceRp == 20_000)
        #expect(sale.totalRp == 24_000)
        #expect(sale.lines?.first?.unitPriceRp == 12_000)
        #expect(sale.lines?.first?.lineTotalRp == 24_000)
    }

    @Test("AC-04-14/R-04-3: soft-deleting a product leaves nameSnapshot readable")
    func test_AC0414_R0403_softDeleteLeavesTheSnapshotReadable() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        let sale = try wiring.sales.complete(lines: [draft(chitato, qty: 2)],
                                             method: .cash, cashReceivedRp: 50_000,
                                             customer: nil)
        try wiring.catalogue.softDelete(chitato)

        #expect(try wiring.catalogue.all().isEmpty)
        #expect(sale.lines?.first?.nameSnapshot == "Chitato Sapi Panggang 68g")
        #expect(sale.lines?.first?.unitPriceRp == 12_000)
        // The weak productID survives; it never became a cascade (D-15).
        #expect(sale.lines?.first?.productID == chitato.id)
    }

    @Test("04 §8: a product soft-deleted mid-cart still completes, onto its own ledger")
    func test_softDeletedMidCartStillCompletes() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let line = draft(chitato, qty: 2)

        // Scanned into the cart, then deleted from the Produk tab.
        try wiring.catalogue.softDelete(chitato)

        let sale = try wiring.sales.complete(lines: [line], method: .cash,
                                             cashReceivedRp: 50_000, customer: nil)

        #expect(sale.totalRp == 24_000)
        #expect(chitato.stockQty == 22)
        let ledger = try wiring.stock.movements(for: chitato)
        #expect(ledger.first?.reason == .sale)
        #expect(ledger.first?.delta == -2)
        #expect(ledger.first?.saleID == sale.id)
    }

    @Test("complete refuses a line whose product does not exist, and writes nothing")
    func test_staleProductReferenceFailsTheWholeTender() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let ghost = DraftLine(productID: UUID(), name: "Hantu",
                              unitPriceRp: 1_000, qty: 1)

        #expect(throws: POSError.productNotFound) {
            _ = try wiring.sales.complete(lines: [self.draft(chitato, qty: 1), ghost],
                                          method: .cash, cashReceivedRp: 50_000,
                                          customer: nil)
        }

        // Money must never move without the stock behind it: the good line did
        // not commit either.
        let after = try committed(wiring)
        #expect(after.sales == 0)
        #expect(after.lines == 0)
        #expect(after.movements == 1)
        #expect(chitato.stockQty == 24)
    }

    // MARK: - R-04-16 — quantity

    @Test("R-04-16: complete refuses a hand-built line at qty 0")
    func test_R0416_zeroQuantityLineIsRejected() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        #expect(throws: POSError.validationFailed(field: "qty")) {
            _ = try wiring.sales.complete(lines: [self.draft(chitato, qty: 0)],
                                          method: .cash, cashReceivedRp: 50_000,
                                          customer: nil)
        }
        #expect(try self.committed(wiring).sales == 0)
    }

    // MARK: - R-04-6 — stock never blocks

    @Test("AC-04-15/R-04-6: selling from zero stock completes and goes negative")
    func test_AC0415_R0406_zeroStockNeverBlocksTheSale() throws {
        let wiring = try TestContainer.sale()
        // §11 STOCK GOES NEGATIVE: Teh Botol at 0, operator sells 3.
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 0)
        #expect(tehBotol.stockQty == 0)

        let sale = try wiring.sales.complete(lines: [draft(tehBotol, qty: 3)],
                                             method: .cash, cashReceivedRp: 20_000,
                                             customer: nil)

        #expect(sale.totalRp == 15_000)
        #expect(tehBotol.stockQty == -3)
        #expect(try wiring.stock.movements(for: tehBotol).first?.delta == -3)
    }

    // MARK: - AC-04-9 — one movement per line

    @Test("AC-04-9: complete writes exactly one .sale movement per line, each carrying the sale ID")
    func test_AC0409_oneSaleMovementPerLine() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let tehBotol = try makeProduct(wiring, name: "Teh Botol Sosro 350ml",
                                       priceRp: 5_000, stockQty: 12)

        let sale = try wiring.sales.complete(
            lines: [draft(chitato, qty: 2), draft(tehBotol, qty: 1)],
            method: .cash, cashReceivedRp: 50_000, customer: nil
        )

        let chitatoSaleMovements = try wiring.stock.movements(for: chitato)
            .filter { $0.reason == .sale }
        let tehBotolSaleMovements = try wiring.stock.movements(for: tehBotol)
            .filter { $0.reason == .sale }

        #expect(chitatoSaleMovements.count == 1)
        #expect(chitatoSaleMovements[0].delta == -2)
        #expect(chitatoSaleMovements[0].saleID == sale.id)
        #expect(tehBotolSaleMovements.count == 1)
        #expect(tehBotolSaleMovements[0].delta == -1)
        #expect(tehBotolSaleMovements[0].saleID == sale.id)

        // 04 §8: one instant for the number, the sale, and every movement.
        #expect(chitatoSaleMovements[0].createdAt == sale.createdAt)
        #expect(tehBotolSaleMovements[0].createdAt == sale.createdAt)
    }

    // MARK: - Customer

    @Test("R-02-5: an attached customer lands on both columns, or on neither")
    func test_customerPairsBothColumns() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)
        let ibuSari = ContactRef(id: "ABC-123", name: "Ibu Sari")

        let withCustomer = try wiring.sales.complete(lines: [draft(chitato, qty: 1)],
                                                     method: .qris, cashReceivedRp: nil,
                                                     customer: ibuSari)
        #expect(withCustomer.customerContactID == "ABC-123")
        #expect(withCustomer.customerName == "Ibu Sari")
        #expect(withCustomer.customer == ibuSari)

        let without = try wiring.sales.complete(lines: [draft(chitato, qty: 1)],
                                                method: .qris, cashReceivedRp: nil,
                                                customer: nil)
        #expect(without.customerContactID == nil)
        #expect(without.customerName == nil)
        #expect(without.customer == nil)
    }

    // MARK: - Reads for module 05

    @Test("sales(onJakartaDay:) returns that day's sales newest first, voided included")
    func test_salesOnJakartaDayIsNewestFirstAndIncludesVoided() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        let first = try wiring.sales.complete(lines: [draft(chitato, qty: 1)],
                                              method: .cash, cashReceivedRp: 12_000,
                                              customer: nil)
        let second = try wiring.sales.complete(lines: [draft(chitato, qty: 1)],
                                               method: .qris, cashReceivedRp: nil,
                                               customer: nil)
        try wiring.sales.void(first, reason: "salah barang")

        let today = try wiring.sales.sales(onJakartaDay: Date())
        #expect(today.count == 2)
        #expect(today[0].id == second.id)          // newest first (R-05-6)
        #expect(today[1].id == first.id)
        #expect(today[1].status == .voided)        // listed, not hidden (R-05-2)

        // A different Jakarta day sees none of them.
        let tomorrow = Date().addingTimeInterval(48 * 60 * 60)
        #expect(try wiring.sales.sales(onJakartaDay: tomorrow).isEmpty)
    }

    @Test("allSales(limit:offset:) windows a newest-first list")
    func test_allSalesWindowsNewestFirst() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        var created: [Sale] = []
        for _ in 0..<5 {
            created.append(try wiring.sales.complete(lines: [draft(chitato, qty: 1)],
                                                     method: .cash, cashReceivedRp: 12_000,
                                                     customer: nil))
        }
        let newestFirst = created.reversed().map(\.id)

        #expect(try wiring.sales.allSales(limit: 2, offset: 0).map(\.id)
                == Array(newestFirst.prefix(2)))
        #expect(try wiring.sales.allSales(limit: 2, offset: 2).map(\.id)
                == Array(newestFirst.dropFirst(2).prefix(2)))
        #expect(try wiring.sales.allSales(limit: 100, offset: 0).count == 5)
        #expect(try wiring.sales.allSales(limit: 100, offset: 5).isEmpty)
        #expect(try wiring.sales.allSales(limit: 0, offset: 0).isEmpty)
    }

    // MARK: - R-04-1 — nothing persists before tender

    @Test("R-04-1: building a cart writes nothing to the store")
    func test_R0401_theCartIsInMemoryOnly() throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, stockQty: 24)

        var cart = SaleDraft()
        cart.add(productID: chitato.id, name: chitato.name, unitPriceRp: chitato.priceRp)
        cart.add(productID: chitato.id, name: chitato.name, unitPriceRp: chitato.priceRp)
        #expect(cart.totalRp == 24_000)

        let after = try committed(wiring)
        #expect(after.sales == 0)
        #expect(after.lines == 0)
        #expect(after.movements == 1)   // the opening, from setup
    }
}

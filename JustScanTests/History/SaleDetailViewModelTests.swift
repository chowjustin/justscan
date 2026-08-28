//
//  SaleDetailViewModelTests.swift
//  JustScanTests
//
//  R-05-4 and the void entry point. The screen renders what was sold at the
//  price it was sold for, and hands a void straight to module 04.
//
//  Not in `STRUCTURE.md` — same precedent as `HistoryViewModelTests`.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct SaleDetailViewModelTests {

    private func draft(_ product: Product, qty: Int) -> DraftLine {
        DraftLine(productID: product.id, name: product.name,
                  unitPriceRp: product.priceRp, qty: qty)
    }

    private func stocked(_ w: TestContainer.SaleWiring,
                         name: String, priceRp: Int, qty: Int) throws -> Product {
        let product = try w.catalogue.create(name: name, priceRp: priceRp,
                                             barcode: nil, supplier: nil)
        try w.stock.record(product: product, delta: qty, reason: .restock,
                           note: nil, saleID: nil)
        return product
    }

    // MARK: - AC-05-6 / R-05-4 — snapshots, never a live lookup

    @Test("AC-05-6/R-05-4: a sale whose product was deleted and replaced still renders the old name and price")
    func test_R0504_AC0506_detailRendersSnapshotsNotTheLiveProduct() throws {
        let w = try TestContainer.sale()
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g",
                                  priceRp: 12_000, qty: 24)
        let sale = try w.sales.complete(lines: [draft(chitato, qty: 2)],
                                        method: .cash, cashReceivedRp: 50_000, customer: nil)

        // §11 DELETED PRODUCT: the product is deleted and a new one created at
        // 15.000 under the same name.
        try w.catalogue.softDelete(chitato)
        _ = try stocked(w, name: "Chitato Sapi Panggang 68g", priceRp: 15_000, qty: 10)

        let model = SaleDetailViewModel(sale: sale, sales: w.sales)

        #expect(model.lines.count == 1)
        #expect(model.lines[0].nameSnapshot == "Chitato Sapi Panggang 68g")
        #expect(model.lines[0].unitPriceRp == 12_000)     // not 15.000
        #expect(model.lines[0].qty == 2)
        #expect(model.lines[0].lineTotalRp == 24_000)
        #expect(model.sale.totalRp == 24_000)

        // "Chitato Sapi Panggang 68g · 2 × 12.000 = 24.000"
        #expect(Rp.format(model.lines[0].unitPriceRp) == "Rp 12.000")
        #expect(Rp.format(model.lines[0].lineTotalRp) == "Rp 24.000")
    }

    @Test("R-05-4: a price edit after the tender never reaches back into the sale")
    func test_R0504_aLaterPriceEditDoesNotReachBack() throws {
        let w = try TestContainer.sale()
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g",
                                  priceRp: 12_000, qty: 24)
        let sale = try w.sales.complete(lines: [draft(chitato, qty: 2)],
                                        method: .cash, cashReceivedRp: 50_000, customer: nil)

        try w.catalogue.update(chitato, name: "Chitato Sapi Panggang 68g",
                               priceRp: 20_000, supplier: nil)

        let model = SaleDetailViewModel(sale: sale, sales: w.sales)
        #expect(chitato.priceRp == 20_000)
        #expect(model.lines[0].unitPriceRp == 12_000)
        #expect(model.lines[0].lineTotalRp == 24_000)
    }

    @Test("foundations §6: lines come back in one deterministic order, not whatever the fetch produced")
    func test_linesAreDeterministicallyOrdered() throws {
        let w = try TestContainer.sale()
        let aqua = try stocked(w, name: "Aqua 600ml", priceRp: 4_000, qty: 24)
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g", priceRp: 12_000, qty: 24)
        let teh = try stocked(w, name: "Teh Botol Sosro 350ml", priceRp: 5_000, qty: 12)

        let sale = try w.sales.complete(
            lines: [draft(teh, qty: 1), draft(chitato, qty: 2), draft(aqua, qty: 3)],
            method: .qris, cashReceivedRp: nil, customer: nil
        )

        let model = SaleDetailViewModel(sale: sale, sales: w.sales)
        let names = model.lines.map(\.nameSnapshot)
        #expect(names == ["Aqua 600ml", "Chitato Sapi Panggang 68g", "Teh Botol Sosro 350ml"])
        // Same answer twice — the point of an explicit sort.
        #expect(model.lines.map(\.nameSnapshot) == names)
    }

    // MARK: - Payment presentation

    @Test("R-04-10/D-08: cash detail shows for a cash sale and is withheld for QRIS")
    func test_R0410_cashDetailIsCashOnly() throws {
        let w = try TestContainer.sale()
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g",
                                  priceRp: 12_000, qty: 24)

        let cash = try w.sales.complete(lines: [draft(chitato, qty: 2)],
                                        method: .cash, cashReceivedRp: 50_000, customer: nil)
        let cashModel = SaleDetailViewModel(sale: cash, sales: w.sales)
        #expect(cashModel.showsCashDetail)
        #expect(cashModel.sale.cashReceivedRp == 50_000)
        #expect(cashModel.sale.changeRp == 26_000)      // 50.000 − 24.000

        let qris = try w.sales.complete(lines: [draft(chitato, qty: 1)],
                                        method: .qris, cashReceivedRp: nil, customer: nil)
        let qrisModel = SaleDetailViewModel(sale: qris, sales: w.sales)
        #expect(!qrisModel.showsCashDetail)
        // nil means "not applicable", never 0.
        #expect(qrisModel.sale.cashReceivedRp == nil)
        #expect(qrisModel.sale.changeRp == nil)
    }

    @Test("05 §8: a customer whose contact was deleted still renders from the name snapshot")
    func test_customerRendersFromTheSnapshot() throws {
        let w = try TestContainer.sale()
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g",
                                  priceRp: 12_000, qty: 24)
        let sale = try w.sales.complete(
            lines: [draft(chitato, qty: 1)],
            method: .qris, cashReceivedRp: nil,
            customer: ContactRef(id: "deleted-contact-identifier", name: "Bu Sri")
        )

        let model = SaleDetailViewModel(sale: sale, sales: w.sales)
        #expect(model.customer?.name == "Bu Sri")
        #expect(model.customer?.id == "deleted-contact-identifier")
    }

    // MARK: - The void, delegated

    @Test("05 §3.2/R-04-12: a completed sale offers Batalkan, a voided one offers none")
    func test_R0412_voidActionDisappearsOnceVoided() throws {
        let w = try TestContainer.sale()
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g",
                                  priceRp: 12_000, qty: 24)
        let sale = try w.sales.complete(lines: [draft(chitato, qty: 2)],
                                        method: .cash, cashReceivedRp: 50_000, customer: nil)

        let model = SaleDetailViewModel(sale: sale, sales: w.sales)
        #expect(!model.isVoided)
        #expect(model.canVoid)
        #expect(!model.didVoid)

        model.void(reason: "salah barang")

        #expect(model.errorMessage == nil)
        #expect(model.didVoid)                       // refreshes the list behind it
        #expect(model.isVoided)
        #expect(!model.canVoid)

        // 05 §3.3: the screen stays open and switches to its voided presentation.
        #expect(model.sale.voidReason == "salah barang")
        #expect(model.sale.voidedAt != nil)
        #expect(model.sale.number == sale.number)    // number retained (D-17)
        #expect(chitato.stockQty == 24)              // stock reversed with the money
    }

    @Test("R-04-12: a second void surfaces saleAlreadyVoided in Indonesian and changes nothing")
    func test_R0412_secondVoidIsRefusedWithAMessage() throws {
        let w = try TestContainer.sale()
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g",
                                  priceRp: 12_000, qty: 24)
        let sale = try w.sales.complete(lines: [draft(chitato, qty: 2)],
                                        method: .cash, cashReceivedRp: 50_000, customer: nil)

        let model = SaleDetailViewModel(sale: sale, sales: w.sales)
        model.void(reason: "salah barang")
        let firstVoidedAt = model.sale.voidedAt

        model.void(reason: "salah lagi")

        #expect(model.errorMessage == POSError.saleAlreadyVoided.message)
        #expect(model.errorMessage == "Transaksi ini sudah dibatalkan.")
        #expect(model.sale.voidReason == "salah barang")
        #expect(model.sale.voidedAt == firstVoidedAt)
        #expect(chitato.stockQty == 24)              // not reversed twice

        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    @Test("R-04-14: a blank reason is refused by module 04 and surfaced, not swallowed")
    func test_R0414_blankReasonIsRefused() throws {
        let w = try TestContainer.sale()
        let chitato = try stocked(w, name: "Chitato Sapi Panggang 68g",
                                  priceRp: 12_000, qty: 24)
        let sale = try w.sales.complete(lines: [draft(chitato, qty: 2)],
                                        method: .cash, cashReceivedRp: 50_000, customer: nil)

        let model = SaleDetailViewModel(sale: sale, sales: w.sales)
        model.void(reason: "   ")

        #expect(model.errorMessage == POSError.validationFailed(field: "reason").message)
        #expect(!model.didVoid)
        #expect(!model.isVoided)
        #expect(chitato.stockQty == 22)
    }
}

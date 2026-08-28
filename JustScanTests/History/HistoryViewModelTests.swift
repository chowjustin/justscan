//
//  HistoryViewModelTests.swift
//  JustScanTests
//
//  The screen's own decisions: which Jakarta day the segmented control points
//  at, what the card says on an empty day, how `Semua` pages and groups, and
//  whether a void refreshes the list in place.
//
//  Not in `STRUCTURE.md` — added for the same reason session 3 added
//  `CatalogueViewModelTests` and session 4 `TenderViewModelTests`: these are
//  decisions, a View may not make them, and views themselves are never tested.
//
//  Sales are inserted through `SwiftDataSaleRepository` directly rather than
//  through `SaleService.complete`, which allocates `createdAt` from `Date()` —
//  a test that cannot choose the instant cannot test a day boundary.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct HistoryViewModelTests {

    // MARK: - Wiring

    private struct Wiring {
        let container: ModelContainer
        let context: ModelContext
        let products: ProductRepository
        let saleRecords: SaleRepository
        let catalogue: CatalogueServicing
        let stock: StockServicing
        let sales: SaleServicing
    }

    private func wiring() throws -> Wiring {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let products = SwiftDataProductRepository(context: context)
        let movements = SwiftDataStockMovementRepository(context: context)
        let saleRecords = SwiftDataSaleRepository(context: context)
        let stock = StockService(products: products, movements: movements)
        return Wiring(
            container: container,
            context: context,
            products: products,
            saleRecords: saleRecords,
            catalogue: CatalogueService(products: products),
            stock: stock,
            sales: SaleService(sales: saleRecords, products: products, stock: stock)
        )
    }

    private func utc(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    @discardableResult
    private func insert(_ w: Wiring,
                        _ number: String,
                        at createdAt: Date,
                        totalRp: Int,
                        method: PaymentMethod = .cash,
                        voided: Bool = false) throws -> Sale {
        let sale = Sale(number: number,
                        totalRp: totalRp,
                        method: method,
                        status: voided ? .voided : .completed,
                        voidedAt: voided ? createdAt : nil,
                        voidReason: voided ? "salah barang" : nil,
                        createdAt: createdAt)
        w.saleRecords.insert(sale)
        try w.products.save()
        return sale
    }

    // MARK: - The scopes

    @Test("05 §10: the three scopes are Hari Ini, Kemarin and Semua, and Hari Ini is the launch scope")
    func test_scopesAreTheThreeIndonesianLabels() throws {
        let model = HistoryViewModel(sales: try wiring().sales)

        #expect(model.scope == .today)
        #expect(HistoryViewModel.Scope.allCases.map(\.label) == ["Hari Ini", "Kemarin", "Semua"])
    }

    @Test("R-05-1: Kemarin is the previous Jakarta day, and Hari Ini and Kemarin read different sales")
    func test_R0501_yesterdayIsThePreviousJakartaDay() throws {
        let w = try wiring()
        // 12:00 WIB on 22 Aug, pinned so the test does not depend on the clock.
        let now = utc("2026-08-22T05:00:00Z")

        try insert(w, "20260822-001", at: utc("2026-08-22T03:00:00Z"), totalRp: 7_000, method: .qris)
        try insert(w, "20260821-001", at: utc("2026-08-21T03:00:00Z"), totalRp: 29_000)

        let model = HistoryViewModel(sales: w.sales, now: { now })

        model.load()
        #expect(model.day == utc("2026-08-21T17:00:00Z"))       // 22 Aug 00:00 WIB
        #expect(model.sales.map(\.number) == ["20260822-001"])
        #expect(model.summary.totalRp == 7_000)

        model.scope = .yesterday
        model.load()
        #expect(model.day == utc("2026-08-20T17:00:00Z"))       // 21 Aug 00:00 WIB
        #expect(model.sales.map(\.number) == ["20260821-001"])
        #expect(model.summary.totalRp == 29_000)

        // Exactly one Jakarta day apart, not 24 hours of device timezone.
        #expect(JakartaDay.previousDay(now) == utc("2026-08-20T17:00:00Z"))
    }

    @Test("AC-05-5/R-05-1: the §11 boundary sales land on 21 and 22 August WIB whatever the device says")
    func test_R0501_AC0505_boundarySalesLandOnDifferentJakartaDays() throws {
        let w = try wiring()
        // 23:58 WIB on 21 Aug and 00:03 WIB on 22 Aug — the same UTC day.
        try insert(w, "20260821-009", at: utc("2026-08-21T16:58:00Z"), totalRp: 10_000)
        try insert(w, "20260822-001", at: utc("2026-08-21T17:03:00Z"), totalRp: 7_000, method: .qris)

        for identifier in ["UTC", "America/Los_Angeles", "Asia/Jakarta"] {
            let original = NSTimeZone.default
            NSTimeZone.default = TimeZone(identifier: identifier)!
            defer { NSTimeZone.default = original }

            let on22 = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-22T05:00:00Z") })
            on22.load()
            #expect(on22.sales.map(\.number) == ["20260822-001"])
            #expect(on22.summary.totalRp == 7_000)

            on22.scope = .yesterday
            on22.load()
            #expect(on22.sales.map(\.number) == ["20260821-009"])
            #expect(on22.summary.totalRp == 10_000)
        }
    }

    // MARK: - AC-05-4 / R-05-7 — the empty day

    @Test("AC-05-4/R-05-7: an empty day shows Rp 0 and 0 transaksi with its own message, not an error")
    func test_R0507_AC0504_emptyDayIsZeroAndNotAnError() throws {
        let w = try wiring()
        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-22T05:00:00Z") })

        model.load()

        #expect(model.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.showsSummaryCard)                     // the card is still there
        #expect(model.summary.totalRp == 0)
        #expect(model.summary.saleCount == 0)
        #expect(model.summary.cashRp == 0)
        #expect(model.summary.qrisRp == 0)
        #expect(Rp.format(model.summary.totalRp) == "Rp 0")
        #expect(model.emptyMessage == "Belum ada transaksi hari ini")

        model.scope = .yesterday
        model.load()
        #expect(model.emptyMessage == "Belum ada transaksi kemarin")

        model.scope = .all
        model.load()
        #expect(model.emptyMessage == "Belum ada transaksi")
        #expect(model.groups.isEmpty)
        #expect(!model.canLoadMore)
        #expect(model.errorMessage == nil)
    }

    // MARK: - AC-05-1 / AC-05-2 / R-05-2 — the worked example through the screen

    @Test("AC-05-1/AC-05-2/R-05-2: the §11 day reads 46.000 over four listed rows, one struck through")
    func test_R0502_AC0501_workedExampleThroughTheScreen() throws {
        let w = try wiring()
        try insert(w, "20260821-001", at: utc("2026-08-21T03:12:00Z"), totalRp: 29_000, method: .cash)
        try insert(w, "20260821-002", at: utc("2026-08-21T04:40:00Z"), totalRp: 12_000, method: .qris)
        try insert(w, "20260821-003", at: utc("2026-08-21T07:05:00Z"), totalRp: 8_000, method: .cash,
                   voided: true)
        try insert(w, "20260821-004", at: utc("2026-08-21T09:22:00Z"), totalRp: 5_000, method: .qris)

        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-21T10:00:00Z") })
        model.load()

        // Four rows listed, newest first (R-05-6).
        #expect(model.sales.map(\.number) == ["20260821-004", "20260821-003",
                                              "20260821-002", "20260821-001"])
        // The voided one is present and is what the row will strike through.
        #expect(model.sales.first { $0.number == "20260821-003" }?.status == .voided)

        #expect(model.summary.totalRp == 46_000)
        #expect(model.summary.saleCount == 3)
        #expect(model.summary.cashRp == 29_000)
        #expect(model.summary.qrisRp == 17_000)
        #expect(model.summary.voidedCount == 1)
        #expect(model.summary.cashRp + model.summary.qrisRp == model.summary.totalRp)
    }

    // MARK: - AC-05-8 / R-05-6 — order

    @Test("AC-05-8/R-05-6: two sales whose numbers and timestamps disagree come back createdAt-descending")
    func test_R0506_AC0508_ordersByCreatedAtNotByNumber() throws {
        let w = try wiring()
        // -002 was rung up an hour *before* -001. A string sort on `number`
        // would put -001 first; `createdAt` descending puts it first too, so
        // the numbers are swapped to make the two orders disagree.
        try insert(w, "20260821-002", at: utc("2026-08-21T09:00:00Z"), totalRp: 20_000)
        try insert(w, "20260821-001", at: utc("2026-08-21T03:00:00Z"), totalRp: 10_000)

        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-21T10:00:00Z") })
        model.load()

        #expect(model.sales.map(\.number) == ["20260821-002", "20260821-001"])
        #expect(model.sales.map(\.number).sorted() != model.sales.map(\.number))

        model.scope = .all
        model.load()
        #expect(model.groups.count == 1)
        #expect(model.groups[0].sales.map(\.number) == ["20260821-002", "20260821-001"])
    }

    // MARK: - Semua: grouping, subtotals, paging

    @Test("05 §3.4: Semua groups by Jakarta day, newest day first, each with its own subtotal")
    func test_semuaGroupsByJakartaDayWithSubtotals() throws {
        let w = try wiring()
        try insert(w, "20260821-001", at: utc("2026-08-21T03:00:00Z"), totalRp: 29_000)
        try insert(w, "20260822-001", at: utc("2026-08-22T03:00:00Z"), totalRp: 12_000, method: .qris)
        try insert(w, "20260822-002", at: utc("2026-08-22T09:00:00Z"), totalRp: 8_000, voided: true)
        try insert(w, "20260823-001", at: utc("2026-08-23T03:00:00Z"), totalRp: 5_000, method: .qris)

        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-23T10:00:00Z") })
        model.scope = .all
        model.load()

        #expect(model.isGrouped)
        #expect(!model.showsSummaryCard)            // no all-time card under Semua
        #expect(model.groups.count == 3)
        #expect(model.groups.map(\.summary.totalRp) == [5_000, 12_000, 29_000])
        #expect(model.groups.map(\.sales.count) == [1, 2, 1])
        // R-05-2 holds inside a section subtotal too.
        #expect(model.groups[1].summary.voidedCount == 1)
        #expect(model.groups[1].summary.saleCount == 1)
        // Nothing more to load, so every subtotal is complete and shown.
        #expect(!model.canLoadMore)
        #expect(model.groups.allSatisfy { model.showsSubtotal(for: $0) })
    }

    @Test("05 §8: Semua pages 100 at a time and appends, and the trailing partial day withholds its subtotal")
    func test_semuaPagesAndWithholdsThePartialSubtotal() throws {
        let w = try wiring()
        // 150 sales on one Jakarta day, one a minute, plus one on the day before.
        let base = utc("2026-08-22T01:00:00Z")
        for index in 0..<150 {
            try insert(w, String(format: "20260822-%03d", index + 1),
                       at: base.addingTimeInterval(Double(index) * 60),
                       totalRp: 1_000)
        }
        try insert(w, "20260821-001", at: utc("2026-08-21T03:00:00Z"), totalRp: 29_000)

        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-22T10:00:00Z") })
        model.scope = .all
        model.load()

        #expect(model.sales.count == HistoryViewModel.pageSize)
        #expect(model.canLoadMore)
        #expect(model.groups.count == 1)
        // The only visible day is half-loaded, so its subtotal is withheld.
        #expect(!model.showsSubtotal(for: model.groups[0]))
        // Newest first: the last of the 150 leads.
        #expect(model.sales.first?.number == "20260822-150")

        model.loadMore()
        #expect(model.sales.count == 151)
        #expect(!model.canLoadMore)
        #expect(model.groups.count == 2)
        #expect(model.groups[0].summary.totalRp == 150_000)
        #expect(model.groups[1].summary.totalRp == 29_000)
        // Everything is loaded, so every subtotal is honest.
        #expect(model.groups.allSatisfy { model.showsSubtotal(for: $0) })

        // Past the end changes nothing.
        model.loadMore()
        #expect(model.sales.count == 151)
    }

    @Test("loadMore is Semua only — a single Jakarta day is never paged")
    func test_loadMoreIsIgnoredOutsideSemua() throws {
        let w = try wiring()
        try insert(w, "20260821-001", at: utc("2026-08-21T03:00:00Z"), totalRp: 29_000)

        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-21T10:00:00Z") })
        model.load()

        #expect(!model.canLoadMore)
        model.loadMore()
        #expect(model.sales.count == 1)
    }

    // MARK: - AC-05-7 — a void refreshes the list and the summary

    @Test("AC-05-7: a void refreshes the day's list and summary in place")
    func test_AC0507_voidRefreshesTheDayInPlace() throws {
        let w = try wiring()
        let product = try w.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                             priceRp: 12_000, barcode: nil, supplier: nil)
        try w.stock.record(product: product, delta: 24, reason: .restock,
                           note: nil, saleID: nil)
        let sale = try w.sales.complete(
            lines: [DraftLine(productID: product.id, name: product.name,
                              unitPriceRp: 12_000, qty: 2)],
            method: .cash, cashReceivedRp: 50_000, customer: nil
        )

        let model = HistoryViewModel(sales: w.sales)
        model.load()
        #expect(model.sales.count == 1)
        #expect(model.summary.totalRp == 24_000)
        #expect(model.summary.saleCount == 1)
        #expect(model.summary.voidedCount == 0)

        let detail = SaleDetailViewModel(sale: sale, sales: w.sales)
        detail.void(reason: "salah barang")
        #expect(detail.errorMessage == nil)

        model.refresh()

        // Still listed (R-05-2), and in no total.
        #expect(model.sales.count == 1)
        #expect(model.sales[0].status == .voided)
        #expect(model.summary.totalRp == 0)
        #expect(model.summary.saleCount == 0)
        #expect(model.summary.cashRp == 0)
        #expect(model.summary.voidedCount == 1)
    }

    @Test("AC-05-7/05 §8: a void under Semua keeps the loaded window rather than collapsing to page one")
    func test_AC0507_refreshKeepsTheLoadedWindow() throws {
        let w = try wiring()
        let base = utc("2026-08-22T01:00:00Z")
        for index in 0..<150 {
            try insert(w, String(format: "20260822-%03d", index + 1),
                       at: base.addingTimeInterval(Double(index) * 60),
                       totalRp: 1_000)
        }

        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-22T10:00:00Z") })
        model.scope = .all
        model.load()
        model.loadMore()
        #expect(model.sales.count == 150)

        // Void the newest row the way the detail screen does.
        let target = model.sales[0]
        try w.sales.void(target, reason: "salah barang")

        model.refresh()

        #expect(model.sales.count == 150)                  // window intact
        #expect(model.sales[0].status == .voided)
        #expect(model.groups.count == 1)
        #expect(model.groups[0].summary.totalRp == 149_000)
        #expect(model.groups[0].summary.voidedCount == 1)
    }

    // MARK: - R-05-3 — nothing is cached

    @Test("R-05-3: the summary is rebuilt on every read and holds no aggregate between them")
    func test_R0503_nothingIsCachedBetweenReads() throws {
        let w = try wiring()
        let model = HistoryViewModel(sales: w.sales, now: { self.utc("2026-08-21T10:00:00Z") })

        model.load()
        #expect(model.summary.totalRp == 0)

        try insert(w, "20260821-001", at: utc("2026-08-21T03:00:00Z"), totalRp: 29_000)
        model.load()
        #expect(model.summary.totalRp == 29_000)

        try insert(w, "20260821-002", at: utc("2026-08-21T04:00:00Z"), totalRp: 12_000, method: .qris)
        model.load()
        #expect(model.summary.totalRp == 41_000)
        #expect(model.summary.qrisRp == 12_000)
    }
}

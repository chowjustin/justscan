//
//  DaySummaryTests.swift
//  JustScanTests
//
//  R-05-1..7 against the pure aggregation, built before any view existed
//  (05 §13.1).
//
//  Every instant here is an ISO-8601 **UTC** literal, so nothing depends on the
//  machine's timezone. That is what makes AC-05-5 real: run this file on a
//  device set to UTC and the Jakarta grouping must not move.
//
//  The §11 worked example is reproduced with its exact numbers — 46.000, 3,
//  29.000, 17.000, 1 — not approximately.
//

import Foundation
import Testing
@testable import JustScan

@MainActor
struct DaySummaryTests {

    // MARK: - Fixtures

    /// UTC instant from ISO-8601, so no test depends on the machine's zone.
    private func utc(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    /// A `Sale` built directly rather than through `SaleService.complete`,
    /// which allocates `createdAt` from `Date()` and would make the §11 clock
    /// times unreachable. `Sale` is storage only, so this is the same object the
    /// service would have produced.
    private func sale(_ number: String,
                      at iso: String,
                      totalRp: Int,
                      method: PaymentMethod,
                      voided: Bool = false) -> Sale {
        Sale(number: number,
             totalRp: totalRp,
             method: method,
             status: voided ? .voided : .completed,
             voidedAt: voided ? utc(iso) : nil,
             voidReason: voided ? "salah barang" : nil,
             createdAt: utc(iso))
    }

    /// The §11 day. Clock times are WIB; the literals are the same instants in
    /// UTC, seven hours earlier.
    ///
    ///     20260821-001   10:12   Tunai   29.000
    ///     20260821-002   11:40   QRIS    12.000
    ///     20260821-003   14:05   Tunai    8.000   ← VOIDED
    ///     20260821-004   16:22   QRIS     5.000
    private var workedExample: [Sale] {
        [
            sale("20260821-004", at: "2026-08-21T09:22:00Z", totalRp: 5_000, method: .qris),
            sale("20260821-003", at: "2026-08-21T07:05:00Z", totalRp: 8_000, method: .cash,
                 voided: true),
            sale("20260821-002", at: "2026-08-21T04:40:00Z", totalRp: 12_000, method: .qris),
            sale("20260821-001", at: "2026-08-21T03:12:00Z", totalRp: 29_000, method: .cash),
        ]
    }

    private var august21: Date { utc("2026-08-21T03:12:00Z") }

    // MARK: - AC-05-1 / R-05-5 — the worked example, exactly

    @Test("AC-05-1/R-05-5: the §11 day is 46.000, 3 transaksi, 29.000 tunai, 17.000 QRIS, 1 dibatalkan")
    func test_R0505_AC0501_workedExampleProducesTheExactNumbers() {
        let summary = DaySummary.of(workedExample, on: august21)

        #expect(summary.totalRp == 46_000)      // 29.000 + 12.000 + 5.000
        #expect(summary.saleCount == 3)         // 4 rows listed, 1 voided
        #expect(summary.cashRp == 29_000)
        #expect(summary.qrisRp == 17_000)       // 12.000 + 5.000
        #expect(summary.voidedCount == 1)

        // R-05-1: the summary is stamped with Jakarta midnight, not UTC midnight.
        #expect(summary.day == utc("2026-08-20T17:00:00Z"))

        // The strings the operator actually reads.
        #expect(Rp.format(summary.totalRp) == "Rp 46.000")
        #expect(Rp.format(summary.cashRp) == "Rp 29.000")
        #expect(Rp.format(summary.qrisRp) == "Rp 17.000")
    }

    // MARK: - AC-05-3 / R-05-5 — the identity, for any dataset

    @Test("AC-05-3/R-05-5: cash + QRIS equals the total for every dataset, including the degenerate ones")
    func test_R0505_AC0503_cashPlusQrisEqualsTotal() {
        let datasets: [[Sale]] = [
            workedExample,
            [],                                                     // empty day
            workedExample.filter { $0.status == .voided },          // every sale voided
            [sale("20260821-001", at: "2026-08-21T03:12:00Z", totalRp: 12_000, method: .qris),
             sale("20260821-002", at: "2026-08-21T04:12:00Z", totalRp: 5_000, method: .qris)],
            [sale("20260821-001", at: "2026-08-21T03:12:00Z", totalRp: 0, method: .cash)],
        ]

        for sales in datasets {
            let summary = DaySummary.of(sales, on: august21)
            #expect(summary.cashRp + summary.qrisRp == summary.totalRp)
        }
    }

    @Test("05 §8: a day whose every sale is voided totals 0 and still reports the voids as context")
    func test_R0502_everySaleVoidedIsZeroWithContext() {
        let allVoided = workedExample.map {
            sale($0.number, at: "2026-08-21T03:12:00Z", totalRp: $0.totalRp,
                 method: $0.method, voided: true)
        }
        let summary = DaySummary.of(allVoided, on: august21)

        #expect(summary.totalRp == 0)
        #expect(summary.saleCount == 0)
        #expect(summary.cashRp == 0)
        #expect(summary.qrisRp == 0)
        #expect(summary.voidedCount == 4)
    }

    // MARK: - AC-05-2 / R-05-2 — listed, but in no total

    @Test("AC-05-2/R-05-2: the voided sale is in no total and is still there to list")
    func test_R0502_AC0502_voidedSaleIsListedAndInNoTotal() {
        let summary = DaySummary.of(workedExample, on: august21)

        // Not in the money: its 8.000 is absent from the total and from tunai.
        #expect(summary.totalRp == 46_000)
        #expect(summary.cashRp == 29_000)
        #expect(summary.saleCount == 3)

        // Still in the ledger: the aggregation never removes a row, so the
        // group the caller renders still carries all four.
        let group = DaySummary.grouped(workedExample)[0]
        #expect(group.sales.count == 4)
        #expect(group.sales.contains { $0.number == "20260821-003" })
        #expect(group.summary.voidedCount == 1)

        // Removing the void from the same day changes the count, not the money.
        let withoutVoid = workedExample.filter { $0.status == .completed }
        let recomputed = DaySummary.of(withoutVoid, on: august21)
        #expect(recomputed.totalRp == summary.totalRp)
        #expect(recomputed.saleCount == summary.saleCount)
        #expect(recomputed.voidedCount == 0)
    }

    // MARK: - R-05-3 — derived at read time

    @Test("R-05-3: the summary is derived at read time and caches nothing")
    func test_R0503_summaryIsDerivedAtReadTime() {
        let sales = workedExample
        let before = DaySummary.of(sales, on: august21)
        #expect(before.totalRp == 46_000)

        // Void the 5.000 QRIS sale the way `SaleService.void` does, then ask
        // again. A cached aggregate would still say 46.000.
        sales[0].statusRaw = SaleStatus.voided.rawValue

        let after = DaySummary.of(sales, on: august21)
        #expect(after.totalRp == 41_000)
        #expect(after.qrisRp == 12_000)
        #expect(after.saleCount == 2)
        #expect(after.voidedCount == 2)

        // And the first answer is untouched — it was a value, not a handle.
        #expect(before.totalRp == 46_000)
    }

    // MARK: - AC-05-5 / R-05-1 — the Jakarta boundary

    @Test("AC-05-5/R-05-1: the §11 boundary sales group into 21 and 22 August WIB, not one UTC day")
    func test_R0501_AC0505_jakartaBoundarySplitsTheTwoSales() {
        // 21 Aug 23:58 WIB and 22 Aug 00:03 WIB are 16:58 and 17:03 on the
        // *same* UTC day. Grouping on UTC would put them together.
        let lateOn21 = sale("20260821-009", at: "2026-08-21T16:58:00Z",
                            totalRp: 10_000, method: .cash)
        let earlyOn22 = sale("20260822-001", at: "2026-08-21T17:03:00Z",
                             totalRp: 7_000, method: .qris)

        #expect(JakartaDay.key(lateOn21.createdAt) == "20260821")
        #expect(JakartaDay.key(earlyOn22.createdAt) == "20260822")
        #expect(JakartaDay.isSameDay(lateOn21.createdAt, earlyOn22.createdAt) == false)

        // Newest first, so 22 Aug leads.
        let groups = DaySummary.grouped([earlyOn22, lateOn21])
        #expect(groups.count == 2)
        #expect(groups[0].summary.totalRp == 7_000)
        #expect(groups[0].sales.map(\.number) == ["20260822-001"])
        #expect(groups[1].summary.totalRp == 10_000)
        #expect(groups[1].sales.map(\.number) == ["20260821-009"])

        // The two group stamps are exactly 24 hours apart — one Jakarta day.
        #expect(groups[0].summary.day.timeIntervalSince(groups[1].summary.day) == 24 * 60 * 60)
    }

    @Test("R-05-1: grouping is Asia/Jakarta even when the process timezone is not")
    func test_R0501_groupingIgnoresTheDeviceTimezone() {
        let sales = [
            sale("20260822-001", at: "2026-08-21T17:03:00Z", totalRp: 7_000, method: .qris),
            sale("20260821-009", at: "2026-08-21T16:58:00Z", totalRp: 10_000, method: .cash),
        ]
        let expected = DaySummary.grouped(sales).map(\.id)

        // `JakartaDay` pins its own calendar, so neither of these can move it.
        for identifier in ["UTC", "America/Los_Angeles", "Pacific/Kiritimati"] {
            let original = NSTimeZone.default
            NSTimeZone.default = TimeZone(identifier: identifier)!
            defer { NSTimeZone.default = original }

            #expect(DaySummary.grouped(sales).map(\.id) == expected)
            #expect(JakartaDay.key(sales[0].createdAt) == "20260822")
            #expect(JakartaDay.key(sales[1].createdAt) == "20260821")
        }
    }

    // MARK: - AC-05-8 / R-05-6 — order

    @Test("AC-05-8/R-05-6: grouping preserves createdAt order and never re-sorts by number")
    func test_R0506_AC0508_groupingPreservesCreatedAtOrder() {
        // Numbers and timestamps disagree: -002 was rung up an hour *before*
        // -001. A string sort on `number` would put -001 first.
        let later = sale("20260821-001", at: "2026-08-21T04:00:00Z",
                         totalRp: 10_000, method: .cash)
        let earlier = sale("20260821-002", at: "2026-08-21T03:00:00Z",
                           totalRp: 20_000, method: .cash)

        // The repository hands the list over newest-first; grouping must not
        // touch that order.
        let groups = DaySummary.grouped([later, earlier])
        #expect(groups.count == 1)
        #expect(groups[0].sales.map(\.number) == ["20260821-001", "20260821-002"])
        #expect(groups[0].sales.map(\.createdAt) == [later.createdAt, earlier.createdAt])
        #expect(groups[0].summary.totalRp == 30_000)
    }

    @Test("R-05-6: three Jakarta days come back newest day first")
    func test_R0506_daysAreNewestFirst() {
        let sales = [
            sale("20260823-001", at: "2026-08-23T03:00:00Z", totalRp: 1_000, method: .cash),
            sale("20260822-002", at: "2026-08-22T09:00:00Z", totalRp: 2_000, method: .cash),
            sale("20260822-001", at: "2026-08-22T03:00:00Z", totalRp: 3_000, method: .qris),
            sale("20260821-001", at: "2026-08-21T03:00:00Z", totalRp: 4_000, method: .cash),
        ]

        let groups = DaySummary.grouped(sales)
        #expect(groups.count == 3)
        #expect(groups.map(\.summary.totalRp) == [1_000, 5_000, 4_000])
        #expect(groups.map(\.sales.count) == [1, 2, 1])
        // Strictly descending day stamps.
        #expect(zip(groups, groups.dropFirst()).allSatisfy { $0.0.summary.day > $0.1.summary.day })
    }

    // MARK: - AC-05-4 / R-05-7 — the empty day

    @Test("AC-05-4/R-05-7: an empty day is Rp 0 and 0 transaksi, never blank and never an error")
    func test_R0507_AC0504_emptyDayIsZeroNotBlank() {
        let empty = DaySummary.of([], on: utc("2026-08-22T05:00:00Z"))

        #expect(empty.totalRp == 0)
        #expect(empty.saleCount == 0)
        #expect(empty.cashRp == 0)
        #expect(empty.qrisRp == 0)
        #expect(empty.voidedCount == 0)

        // §11 EMPTY DAY: "Total Rp 0 · 0 transaksi · Tunai Rp 0 · QRIS Rp 0".
        #expect(Rp.format(empty.totalRp) == "Rp 0")
        #expect(Rp.format(empty.cashRp) == "Rp 0")
        #expect(Rp.format(empty.qrisRp) == "Rp 0")

        // Still stamped with the right Jakarta day, so the card has a date.
        #expect(empty.day == utc("2026-08-21T17:00:00Z"))

        // And no groups at all, which is what drives the empty-list message.
        #expect(DaySummary.grouped([]).isEmpty)
    }
}

//
//  SaleNumberingTests.swift
//  JustScanTests
//
//  R-04-4 — `{YYYYMMDD}-{NNN}`, Asia/Jakarta, gapless, no reuse (D-17).
//
//  Every instant here is built from `JakartaDay.calendar`, never
//  `Calendar.current`, so no test depends on the machine's own zone — the same
//  discipline `JakartaDayTests` uses. `test_R0404_counterRestartsOnTheJakartaDay`
//  goes further and asserts against a UTC calendar directly: both of its
//  instants are the 21st in UTC, so a UTC-based boundary would put them on one
//  receipt sequence when they belong on two.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct SaleNumberingTests {

    // MARK: - Fixed instants from 04 §11

    /// `2026-08-21 23:58 WIB`.
    private static let lateOn21Aug = jakarta(2026, 8, 21, 23, 58)
    /// `2026-08-22 00:03 WIB` — five minutes later, and a different day.
    private static let earlyOn22Aug = jakarta(2026, 8, 22, 0, 3)

    private static func jakarta(_ year: Int, _ month: Int, _ day: Int,
                                _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day
        parts.hour = hour; parts.minute = minute
        return JakartaDay.calendar.date(from: parts)!
    }

    private func makeProduct(_ wiring: TestContainer.SaleWiring) throws -> Product {
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000, barcode: nil,
                                                  supplier: nil)
        try wiring.stock.record(product: product, delta: 200, reason: .opening,
                                note: nil, saleID: nil)
        return product
    }

    private func draft(_ product: Product) -> DraftLine {
        DraftLine(productID: product.id, name: product.name,
                  unitPriceRp: product.priceRp, qty: 1)
    }

    /// A sale that already happened, on a day of our choosing.
    private func backdate(_ wiring: TestContainer.SaleWiring,
                          number: String, at createdAt: Date,
                          status: SaleStatus = .completed) throws {
        let repository = SwiftDataSaleRepository(context: wiring.context)
        repository.insert(Sale(number: number, totalRp: 12_000, method: .cash,
                               cashReceivedRp: 12_000, changeRp: 0,
                               status: status, createdAt: createdAt))
        try wiring.products.save()
    }

    // MARK: - AC-04-7 — the shape and the sequence

    @Test("AC-04-7/R-04-4: the first sale of a Jakarta day is -001 and the eighth is -008")
    func test_AC0407_R0404_firstIs001AndEighthIs008() throws {
        let wiring = try TestContainer.sale()
        let product = try makeProduct(wiring)

        var numbers: [String] = []
        for _ in 0..<8 {
            numbers.append(try wiring.sales.complete(lines: [draft(product)],
                                                     method: .cash,
                                                     cashReceivedRp: 12_000,
                                                     customer: nil).number)
        }

        let today = JakartaDay.key(Date())
        #expect(numbers.first == "\(today)-001")
        #expect(numbers.last == "\(today)-008")
        #expect(numbers == (1...8).map { String(format: "%@-%03d", today, $0) })
    }

    @Test("R-04-4: the number's date half is the Jakarta day of the sale's own createdAt")
    func test_R0404_numberAgreesWithCreatedAt() throws {
        let wiring = try TestContainer.sale()
        let product = try makeProduct(wiring)

        let sale = try wiring.sales.complete(lines: [draft(product)], method: .cash,
                                             cashReceivedRp: 12_000, customer: nil)

        // 04 §8: one instant for the number, the sale, and every movement, so a
        // tender at 23:59:58 whose commit lands at 00:00:01 cannot disagree
        // with itself.
        #expect(sale.number.hasPrefix(JakartaDay.key(sale.createdAt)))
        #expect(sale.number.count == 12)                       // 8 + "-" + 3
        let sequence = sale.number.suffix(3)
        #expect(sequence.allSatisfy { $0.isNumber })
    }

    // MARK: - AC-04-8 — a void does not free a number

    @Test("AC-04-8/R-04-4: voiding a sale does not free its number")
    func test_AC0408_R0404_voidDoesNotFreeTheNumber() throws {
        let wiring = try TestContainer.sale()
        let product = try makeProduct(wiring)
        let today = JakartaDay.key(Date())

        var sales: [Sale] = []
        for _ in 0..<7 {
            sales.append(try wiring.sales.complete(lines: [draft(product)],
                                                   method: .cash,
                                                   cashReceivedRp: 12_000,
                                                   customer: nil))
        }
        #expect(sales.last?.number == "\(today)-007")

        // §11: "Void 20260821-007. The next sale on 21 Aug is still -008."
        try wiring.sales.void(sales[6], reason: "salah barang")
        #expect(sales[6].number == "\(today)-007")             // retained

        let next = try wiring.sales.complete(lines: [draft(product)], method: .cash,
                                             cashReceivedRp: 12_000, customer: nil)
        #expect(next.number == "\(today)-008")                 // no reuse, no gap
    }

    // MARK: - The Jakarta day boundary

    @Test("R-04-4/R-05-1: the counter restarts at the Jakarta midnight, not the UTC one")
    func test_R0404_counterRestartsOnTheJakartaDay() throws {
        let wiring = try TestContainer.sale()
        let repository = SwiftDataSaleRepository(context: wiring.context)

        // §11: 23:58 WIB on the 21st, then 00:03 WIB on the 22nd.
        for index in 1...7 {
            try backdate(wiring,
                         number: String(format: "20260821-%03d", index),
                         at: Self.lateOn21Aug,
                         status: index == 7 ? .voided : .completed)
        }

        #expect(JakartaDay.key(Self.lateOn21Aug) == "20260821")
        #expect(JakartaDay.key(Self.earlyOn22Aug) == "20260822")

        // Voided sales are counted — that is what makes the sequence gapless.
        let on21Aug = try repository.countOfSales(onJakartaDay: Self.lateOn21Aug)
        let on22Aug = try repository.countOfSales(onJakartaDay: Self.earlyOn22Aug)
        #expect(on21Aug == 7)
        // Five minutes later is a new day and a fresh counter.
        #expect(on22Aug == 0)

        // Both instants are the 21st in UTC (16:58 and 17:03), so a UTC-based
        // boundary would have counted seven for both.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.component(.day, from: Self.lateOn21Aug) == 21)
        #expect(utc.component(.day, from: Self.earlyOn22Aug) == 21)
    }

    @Test("R-04-4: yesterday's seven sales do not carry into today's numbering")
    func test_R0404_yesterdayDoesNotCarryOver() throws {
        let wiring = try TestContainer.sale()
        let product = try makeProduct(wiring)

        for index in 1...7 {
            try backdate(wiring, number: String(format: "20260821-%03d", index),
                         at: Self.lateOn21Aug)
        }

        let first = try wiring.sales.complete(lines: [draft(product)], method: .cash,
                                              cashReceivedRp: 12_000, customer: nil)
        #expect(first.number == "\(JakartaDay.key(Date()))-001")
    }

    @Test("R-04-4: a sale one second after Jakarta midnight belongs to the new day")
    func test_R0404_oneSecondPastMidnightIsTheNewDay() throws {
        let midnight = JakartaDay.startOfDay(Self.earlyOn22Aug)
        let justBefore = midnight.addingTimeInterval(-1)
        let justAfter = midnight.addingTimeInterval(1)

        #expect(JakartaDay.key(justBefore) == "20260821")
        #expect(JakartaDay.key(justAfter) == "20260822")
        #expect(!JakartaDay.isSameDay(justBefore, justAfter))
    }
}

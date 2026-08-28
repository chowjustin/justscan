//
//  JakartaDayTests.swift
//  JustScanTests
//
//  The tests that catch real bugs. Every case here is built from a UTC instant
//  and asserted against a Jakarta boundary, so a helper that quietly used
//  `Calendar.current` would fail here on any machine not set to WIB.
//

import Foundation
import Testing
@testable import JustScan

struct JakartaDayTests {
    /// UTC instant from ISO-8601, so no test depends on the machine's zone.
    private func utc(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    @Test("The zone is Asia/Jakarta, UTC+7, and never the device's")
    func test_JakartaDay_isUTCPlus7() {
        #expect(JakartaDay.timeZone.identifier == "Asia/Jakarta")
        // Indonesia has no daylight saving, so the offset is constant.
        #expect(JakartaDay.timeZone.secondsFromGMT(for: utc("2026-01-15T00:00:00Z")) == 7 * 3600)
        #expect(JakartaDay.timeZone.secondsFromGMT(for: utc("2026-07-15T00:00:00Z")) == 7 * 3600)
    }

    @Test("Foundations §6: 08:00 WIB and 06:00 UTC are different Jakarta days")
    func test_JakartaDay_groupsTheWorkedExampleCorrectly() {
        // 08:00 WIB on 21 Aug is 01:00 UTC the same day.
        let morningWIB = utc("2026-08-21T01:00:00Z")
        // 06:00 UTC on 21 Aug is 13:00 WIB the same day.
        let afternoonWIB = utc("2026-08-21T06:00:00Z")
        #expect(JakartaDay.isSameDay(morningWIB, afternoonWIB))
        #expect(JakartaDay.key(morningWIB) == "20260821")
        #expect(JakartaDay.key(afternoonWIB) == "20260821")
    }

    @Test("The day boundary sits at 17:00 UTC the previous day")
    func test_JakartaDay_boundaryIsSeventeenHundredUTC() {
        // 16:59:59 UTC on 20 Aug is 23:59:59 WIB on 20 Aug — still the 20th.
        #expect(JakartaDay.key(utc("2026-08-20T16:59:59Z")) == "20260820")
        // 17:00:00 UTC on 20 Aug is 00:00:00 WIB on 21 Aug — now the 21st.
        #expect(JakartaDay.key(utc("2026-08-20T17:00:00Z")) == "20260821")
        #expect(JakartaDay.isSameDay(
            utc("2026-08-20T16:59:59Z"),
            utc("2026-08-20T17:00:00Z")
        ) == false)
    }

    @Test("startOfDay is Jakarta midnight, expressed as 17:00 UTC the day before")
    func test_JakartaDay_startOfDay() {
        let midday = utc("2026-08-21T05:00:00Z")   // 12:00 WIB
        #expect(JakartaDay.startOfDay(midday) == utc("2026-08-20T17:00:00Z"))
    }

    @Test("endOfDay is an exclusive upper bound exactly 24 hours later")
    func test_JakartaDay_endOfDayIsExclusive() {
        let midday = utc("2026-08-21T05:00:00Z")
        let start = JakartaDay.startOfDay(midday)
        let end = JakartaDay.endOfDay(midday)
        #expect(end == utc("2026-08-21T17:00:00Z"))
        #expect(end.timeIntervalSince(start) == 24 * 60 * 60)
        // The bound belongs to the next day, not this one.
        #expect(JakartaDay.isSameDay(end, midday) == false)
    }

    @Test("range(of:) is half-open and contains its own start but not its end")
    func test_JakartaDay_rangeIsHalfOpen() {
        let midday = utc("2026-08-21T05:00:00Z")
        let range = JakartaDay.range(of: midday)
        #expect(range.contains(range.lowerBound))
        #expect(range.contains(range.upperBound) == false)
        #expect(range.contains(midday))
        #expect(range.contains(utc("2026-08-20T16:59:59Z")) == false)
    }

    @Test("key(_:) zero-pads month and day")
    func test_JakartaDay_keyIsZeroPadded() {
        #expect(JakartaDay.key(utc("2026-01-05T05:00:00Z")) == "20260105")
        #expect(JakartaDay.key(utc("2026-12-31T05:00:00Z")) == "20261231")
    }

    @Test("A year boundary crossed in Jakarta but not in UTC")
    func test_JakartaDay_crossesTheYearBoundaryOnJakartaTime() {
        // 31 Dec 2026 18:00 UTC is 1 Jan 2027 01:00 WIB.
        #expect(JakartaDay.key(utc("2026-12-31T18:00:00Z")) == "20270101")
    }
}

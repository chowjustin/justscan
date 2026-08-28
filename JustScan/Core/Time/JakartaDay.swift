//
//  JakartaDay.swift
//  JustScan
//
//  THE day-boundary helper. Nothing else in this codebase computes a day.
//
//  Every boundary is Asia/Jakarta (WIB, UTC+7) regardless of device timezone
//  (D-16). Grouping on UTC splits a trading day in half: a sale at 08:00 WIB is
//  01:00 UTC the same day, but 06:00 UTC is 13:00 WIB.
//

import Foundation

enum JakartaDay {
    /// Asia/Jakarta. The identifier is fixed; the fallback is the fixed +07:00
    /// offset, because a missing zone database must not silently become UTC.
    static let timeZone: TimeZone =
        TimeZone(identifier: "Asia/Jakarta")
        ?? TimeZone(secondsFromGMT: 7 * 60 * 60)!

    /// A Gregorian calendar pinned to Jakarta. Never `Calendar.current` — the
    /// device's own zone and calendar are exactly what this type exists to ignore.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    /// Midnight in Jakarta on the day containing `date`.
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Midnight in Jakarta on the *following* day — an exclusive upper bound.
    static func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(date))
            ?? startOfDay(date).addingTimeInterval(24 * 60 * 60)
    }

    /// Half-open range covering one Jakarta day: `[start, end)`.
    static func range(of date: Date) -> Range<Date> {
        startOfDay(date)..<endOfDay(date)
    }

    /// `"YYYYMMDD"` in Jakarta — the date half of a sale number (R-04-4).
    static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    /// Whether two instants fall on the same Jakarta day.
    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        startOfDay(a) == startOfDay(b)
    }
}

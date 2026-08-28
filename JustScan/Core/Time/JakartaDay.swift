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

    /// Midnight in Jakarta on the *previous* day — "kemarin" (05 §10).
    ///
    /// It lives here rather than in `HistoryViewModel` for the same reason
    /// everything else in this type does: one helper owns day boundaries, and
    /// no feature computes its own (CONVENTIONS.md).
    static func previousDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: -1, to: startOfDay(date))
            ?? startOfDay(date).addingTimeInterval(-24 * 60 * 60)
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

    /// `d MMM, HH:mm` in Jakarta — the stamp on every ledger and history row
    /// (03 §10). Display only; nothing decides anything from this string.
    ///
    /// It lives here rather than in a feature because the alternative is each
    /// screen building its own formatter, and a formatter that forgets to set
    /// `timeZone` is exactly the bug this type exists to prevent.
    static func shortDateTime(_ date: Date) -> String {
        shortDateTimeFormatter.string(from: date)
    }

    private static let shortDateTimeFormatter = formatter(format: "d MMM, HH:mm")

    /// `HH:mm` in Jakarta — the time on a history row (05 §10).
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// `d MMM yyyy` in Jakarta — a day header and the date half of a full
    /// stamp (05 §10).
    static func longDate(_ date: Date) -> String {
        longDateFormatter.string(from: date)
    }

    /// `d MMM yyyy, HH:mm` — the full timestamp at the top of a sale detail
    /// (05 §10). Composed from the two above so there is one definition of each
    /// half, not three formatters that can drift apart.
    static func fullDateTime(_ date: Date) -> String {
        "\(longDate(date)), \(time(date))"
    }

    private static let timeFormatter = formatter(format: "HH:mm")
    private static let longDateFormatter = formatter(format: "d MMM yyyy")

    /// Every formatter in this file is built here, so none of them can be
    /// declared without its `timeZone` — the exact bug this type exists to
    /// prevent.
    private static func formatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.dateFormat = format
        return formatter
    }

    /// Whether two instants fall on the same Jakarta day.
    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        startOfDay(a) == startOfDay(b)
    }
}

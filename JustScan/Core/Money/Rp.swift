//
//  Rp.swift
//  JustScan
//
//  Integer rupiah, always (R-01-1, D-09). IDR has no circulating subunit,
//  so an Int is exact and needs no scaling factor.
//
//  The name is deliberate: the unit outlives the app (CONVENTIONS.md).
//

import Foundation

enum Rp {
    /// `12000` → `"Rp 12.000"`, `0` → `"Rp 0"`, `-21000` → `"-Rp 21.000"` (R-01-2).
    ///
    /// Built from a plain grouping formatter rather than a currency formatter on
    /// purpose. `id_ID` currency output carries a non-breaking space (U+00A0)
    /// between the symbol and the digits and two decimal places, neither of which
    /// matches the strings §11 pins exactly.
    static func format(_ amount: Int) -> String {
        // `.magnitude`, not `abs()`: abs(Int.min) traps.
        let digits = grouped(amount.magnitude)
        return amount < 0 ? "-Rp \(digits)" : "Rp \(digits)"
    }

    private static let groupingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static func grouped(_ magnitude: UInt) -> String {
        groupingFormatter.string(from: NSNumber(value: magnitude)) ?? String(magnitude)
    }
}

//
//  BarcodeKind.swift
//  JustScan
//
//  Classifies a scanned string so module 03 can warn the operator (R-03-8).
//  Classification only — this type never decides what to do about it.
//

import Foundation

enum BarcodeKind: Equatable, Sendable {
    /// A real product code we can treat as an identity.
    case gtin
    /// A store or scale code. The digits encode weight or price, so the same
    /// product produces a different code on every package.
    case internalCode
    /// Not a code shape we recognise.
    case unknown
}

extension BarcodeKind {
    /// R-01-8. A string qualifies only if it is **all digits** and 8, 12, or 13
    /// characters long. Of those, prefix `02` or `20`–`29` is an internal code;
    /// everything else in that set is a GTIN. Anything else is `.unknown`,
    /// including a prefix-matching but non-numeric string such as `"02ABC"`.
    static func of(_ raw: String) -> BarcodeKind {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard acceptedLengths.contains(code.count),
              code.allSatisfy(\.isASCIIDigit)
        else { return .unknown }

        return hasInternalPrefix(code) ? .internalCode : .gtin
    }

    /// EAN-8, UPC-A, EAN-13. A 6-digit UPC-E payload is deliberately excluded
    /// and classifies as `.unknown` — an accepted gap, recorded in 01 §11.
    private static let acceptedLengths: Set<Int> = [8, 12, 13]

    private static func hasInternalPrefix(_ code: String) -> Bool {
        let prefix = code.prefix(2)
        // `02` — in-store. `20`–`29` — variable weight.
        return prefix == "02" || prefix.first == "2"
    }
}

private extension Character {
    /// Deliberately ASCII-only. `Character.isNumber` accepts Arabic-Indic and
    /// other digit forms, which a barcode scanner never emits and which would
    /// break the fixed-width parsing every caller assumes.
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}

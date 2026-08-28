//
//  StockReason.swift
//  JustScan
//
//  Declared in Core/Stock/ because module 04 records movements too (STRUCTURE.md).
//  The reasons themselves are 03 §5; the rules that pick between them are 03's.
//

import Foundation

/// Exactly these five. `sale` and `void` carry a non-nil `saleID`;
/// the other three carry nil (R-03-13).
enum StockReason: String, CaseIterable, Sendable {
    case opening
    case restock
    case sale
    case void
    case adjustment
}

extension StockReason {
    /// R-03-13, expressed so `StockService.record` can enforce the pairing
    /// rather than trust its callers. A `sale` or `void` movement without a
    /// `saleID` — or an `opening`/`restock`/`adjustment` carrying one — is a
    /// ledger row nobody can trace back, so it is rejected at the boundary.
    var requiresSaleID: Bool {
        switch self {
        case .sale, .void:
            return true
        case .opening, .restock, .adjustment:
            return false
        }
    }
}

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

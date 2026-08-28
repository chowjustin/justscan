//
//  StockMovement.swift
//  JustScan
//
//  Storage only. Owned by module 03. Movements are immutable and never
//  deleted (R-03-10). Fields are verbatim from 03 §5.
//

import Foundation
import SwiftData

@Model final class StockMovement {
    var id: UUID = UUID()

    var product: Product?

    /// Signed delta. Never zero in practice (R-03-13, 03 §8).
    var delta: Int = 0

    /// Backing store for `StockReason`. A raw `String`, not an enum, for
    /// schema-evolution safety (foundations §6).
    var reasonRaw: String = StockReason.adjustment.rawValue

    var note: String?

    /// Set iff `reason` is `.sale` or `.void` (R-03-13).
    var saleID: UUID?

    var createdAt: Date = Date()

    /// Typed accessor with an explicit unknown-value fallback (foundations §6).
    var reason: StockReason {
        StockReason(rawValue: reasonRaw) ?? .adjustment
    }

    init(
        id: UUID = UUID(),
        product: Product? = nil,
        delta: Int = 0,
        reason: StockReason = .adjustment,
        note: String? = nil,
        saleID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.product = product
        self.delta = delta
        self.reasonRaw = reason.rawValue
        self.note = note
        self.saleID = saleID
        self.createdAt = createdAt
    }
}

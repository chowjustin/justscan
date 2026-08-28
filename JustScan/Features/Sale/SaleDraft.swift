//
//  SaleDraft.swift
//  JustScan
//
//  The cart, and nothing else. In-memory only — a `struct` with no repository,
//  no context, and no way to reach one (R-04-1, D-14).
//
//  Tender is the pivot event: before it the cart is free, after it the sale is
//  immutable (04 §1). A force-quit mid-cart loses the cart, and that is the
//  accepted trade for never writing a half-finished sale.
//

import Foundation

/// One product in a cart, priced at the moment it was scanned.
///
/// The price is captured here rather than read at tender: the line was quoted
/// to the customer, so a price edited in another tab mid-cart does not change
/// it (R-04-3, 04 §8).
struct DraftLine: Equatable {
    let productID: UUID
    let name: String
    let unitPriceRp: Int
    var qty: Int
    var lineTotalRp: Int { unitPriceRp * qty }
}

/// The in-memory cart. Owns the R-04-2 merge and the R-04-16 quantity rule, so
/// the ViewModel above it only has to decide *when* to call these.
struct SaleDraft: Equatable {
    /// Newest first — the operator watches the thing they just scanned appear
    /// where their eye already is (04 §10).
    private(set) var lines: [DraftLine] = []

    var isEmpty: Bool { lines.isEmpty }

    /// Σ of line totals. Integer rupiah throughout; no other numeric type
    /// appears anywhere on this path (D-09).
    var totalRp: Int { lines.reduce(0) { $0 + $1.lineTotalRp } }

    /// R-04-2. A sale never contains two lines for the same product: scanning
    /// something already in the cart increments the line that is there.
    /// Scanning the same packet five times is one line at qty 5 (04 §8).
    mutating func add(productID: UUID, name: String, unitPriceRp: Int) {
        if let index = lines.firstIndex(where: { $0.productID == productID }) {
            lines[index].qty += 1
        } else {
            lines.insert(
                DraftLine(productID: productID, name: name,
                          unitPriceRp: unitPriceRp, qty: 1),
                at: 0
            )
        }
    }

    /// R-04-16. Quantity is an `Int` ≥ 1; setting it to zero or below removes
    /// the line rather than leaving a line that sells nothing.
    mutating func setQty(_ qty: Int, for productID: UUID) {
        guard let index = lines.firstIndex(where: { $0.productID == productID })
        else { return }

        if qty < 1 {
            lines.remove(at: index)
        } else {
            lines[index].qty = qty
        }
    }

    mutating func remove(productID: UUID) {
        lines.removeAll { $0.productID == productID }
    }

    /// Discarding the whole cart. Nothing was persisted, so nothing is undone.
    mutating func clear() {
        lines = []
    }
}

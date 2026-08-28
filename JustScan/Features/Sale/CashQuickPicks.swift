//
//  CashQuickPicks.swift
//  JustScan
//
//  R-04-9, as a pure function over `Int` — no view, no state, no formatting.
//  The chips are the notes an Indonesian customer actually hands over, so the
//  operator taps once instead of typing five digits at a counter.
//

import Foundation

enum CashQuickPicks {
    /// The denominations a total is rounded **up** to. 20.000 is in the list
    /// because it is a circulating note, even though it is not a power of ten.
    static let denominations = [5_000, 10_000, 20_000, 50_000, 100_000]

    /// R-04-9: the total rounded up to the next 5k, 10k, 20k, 50k and 100k,
    /// deduplicated, **excluding any equal to the total** — a chip that offers
    /// the exact amount is what the separate "Pas" chip is for.
    ///
    /// Ascending, which is the order 04 §11 pins:
    /// `29.000 → 30.000 · 40.000 · 50.000 · 100.000` (30.000 arrives from both
    /// the 5k and the 10k round-up and appears once).
    ///
    /// A total that is already a round 30.000 drops 30.000 from the list by the
    /// same exclusion rule, and the operator taps "Pas".
    static func amounts(forTotalRp totalRp: Int) -> [Int] {
        guard totalRp > 0 else { return [] }

        var seen = Set<Int>()
        var result: [Int] = []

        for denomination in denominations {
            let roundedUp = roundUp(totalRp, to: denomination)
            guard roundedUp != totalRp, seen.insert(roundedUp).inserted else { continue }
            result.append(roundedUp)
        }
        return result.sorted()
    }

    /// The smallest multiple of `denomination` that is ≥ `amount`.
    private static func roundUp(_ amount: Int, to denomination: Int) -> Int {
        let remainder = amount % denomination
        return remainder == 0 ? amount : amount + (denomination - remainder)
    }
}

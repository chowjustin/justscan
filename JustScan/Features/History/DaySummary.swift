//
//  DaySummary.swift
//  JustScan
//
//  The only type module 05 defines, and it is not an entity (05 §5). Every
//  figure on a history screen is derived from stored `Sale.totalRp` values at
//  read time; nothing here is stored and nothing is cached (R-05-3).
//
//  Two rules are structural rather than remembered:
//
//  · R-05-2 — the four aggregates are computed over `completed` only, while the
//    caller keeps every row to list. A voided sale is excluded from the money
//    and counted separately, never hidden. Hiding it would make the ledger a lie.
//
//  · R-05-5 — cash and QRIS are a **partition** of the same completed set, and
//    `totalRp` is their sum. The identity `cashRp + qrisRp == totalRp` therefore
//    holds by construction for any dataset (AC-05-3), not because three
//    independent sums happen to agree.
//
//  Every day boundary comes from `JakartaDay` (R-05-1, D-16).
//

import Foundation

struct DaySummary: Equatable {
    let day: Date          // Jakarta midnight
    let totalRp: Int       // completed only
    let saleCount: Int     // completed only
    let cashRp: Int
    let qrisRp: Int
    let voidedCount: Int   // shown as context, excluded from totals
}

extension DaySummary {
    /// The aggregation. Pure: same input, same answer, no store behind it.
    ///
    /// `sales` is whatever the caller decided belongs to `day` — this function
    /// does not filter by date, so a caller that hands it the wrong day gets a
    /// summary of the wrong day rather than a silently empty one.
    static func of(_ sales: [Sale], on day: Date) -> DaySummary {
        let completed = sales.filter { $0.status == .completed }   // R-05-2
        let cashRp = sum(completed, method: .cash)                 // R-05-5
        let qrisRp = sum(completed, method: .qris)

        return DaySummary(
            day: JakartaDay.startOfDay(day),                       // R-05-1
            totalRp: cashRp + qrisRp,
            saleCount: completed.count,
            cashRp: cashRp,
            qrisRp: qrisRp,
            voidedCount: sales.count - completed.count
        )
    }

    /// One Jakarta day of sales, with its own summary. `Semua` renders one
    /// section per group (05 §3, §10).
    struct Group: Identifiable {
        let summary: DaySummary
        let sales: [Sale]

        /// The Jakarta midnight the group covers — unique within a list by
        /// construction, since a day appears at most once.
        var id: Date { summary.day }
    }

    /// Splits a `createdAt`-descending list into Jakarta days, newest day first.
    ///
    /// Order-preserving: it walks the list and breaks where the Jakarta day
    /// changes, rather than bucketing and re-sorting. That keeps R-05-6 the
    /// repository's single responsibility — nothing here re-sorts, and nothing
    /// anywhere sorts by `number`, whose string order is only accidentally
    /// correct.
    static func grouped(_ sales: [Sale]) -> [Group] {
        var groups: [Group] = []
        var current: [Sale] = []

        for sale in sales {
            if let first = current.first,
               !JakartaDay.isSameDay(first.createdAt, sale.createdAt) {
                groups.append(group(current))
                current = []
            }
            current.append(sale)
        }
        if !current.isEmpty { groups.append(group(current)) }

        return groups
    }

    private static func group(_ sales: [Sale]) -> Group {
        // Safe: `grouped` never calls this with an empty slice.
        let day = sales[0].createdAt
        return Group(summary: of(sales, on: day), sales: sales)
    }

    private static func sum(_ sales: [Sale], method: PaymentMethod) -> Int {
        sales.reduce(0) { $0 + ($1.method == method ? $1.totalRp : 0) }
    }
}

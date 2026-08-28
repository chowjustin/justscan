//
//  SaleRepository.swift
//  JustScan
//
//  Fetch, insert, count. No rules, no validation, no decisions — those live in
//  `SaleService` (CONVENTIONS.md, layering).
//
//  There is deliberately no `save()` here — see `ProductRepository.save()`.
//  A sale, its lines, and every stock movement it causes are one business
//  operation and therefore one commit (R-04-15).
//
//  Every day boundary comes from `JakartaDay`. Nothing in this file computes a
//  day of its own (R-05-1, D-16).
//

import Foundation
import SwiftData

protocol SaleRepository {
    /// Stage an insert. Not committed until `ProductRepository.save()`.
    func insert(_ sale: Sale)

    /// Stage a line. Inserted explicitly rather than left to the relationship,
    /// so the object is in the context before the single commit runs.
    func insert(_ line: SaleLine)

    /// How many sales already exist on that Jakarta day, **voided included**.
    ///
    /// This is the whole of sale numbering (R-04-4): the next number is this
    /// plus one. Voided sales keep their number and still consume it, which is
    /// why nothing is filtered here — a gap in a receipt sequence is
    /// indistinguishable from a hidden sale (D-17).
    func countOfSales(onJakartaDay day: Date) throws -> Int

    /// That Jakarta day's sales, newest first. Voided sales are included;
    /// excluding them from *totals* is module 05's job (R-05-2).
    func sales(onJakartaDay day: Date) throws -> [Sale]

    /// Every sale, newest first, windowed. `createdAt` descending — never
    /// `number`, whose string order is only accidentally correct (R-05-6).
    func all(limit: Int, offset: Int) throws -> [Sale]
}

struct SwiftDataSaleRepository: SaleRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insert(_ sale: Sale) {
        context.insert(sale)
    }

    func insert(_ line: SaleLine) {
        context.insert(line)
    }

    func countOfSales(onJakartaDay day: Date) throws -> Int {
        try sales(onJakartaDay: day).count
    }

    func sales(onJakartaDay day: Date) throws -> [Sale] {
        let range = JakartaDay.range(of: day)
        return try newestFirst()
            .filter { range.contains($0.createdAt) }
    }

    func all(limit: Int, offset: Int) throws -> [Sale] {
        // Windowed in memory rather than by descriptor. Foundations §8 sizes
        // this at ~18,000 rows a year, and 05 §8 makes this the only paged
        // list in the app; a fetch limit here would still have to be paired
        // with the same sort, and this keeps one code path.
        let all = try newestFirst()
        guard limit > 0, offset < all.count else { return [] }
        let start = max(0, offset)
        let end = min(all.count, start + limit)
        return Array(all[start..<end])
    }

    /// No ordered relationships anywhere in this schema (foundations §6), so
    /// order is always an explicit `SortDescriptor`.
    private func newestFirst() throws -> [Sale] {
        let descriptor = FetchDescriptor<Sale>(
            sortBy: [SortDescriptor(\Sale.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
}

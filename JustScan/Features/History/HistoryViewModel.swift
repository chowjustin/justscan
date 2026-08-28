//
//  HistoryViewModel.swift
//  JustScan
//
//  Every decision the Riwayat screen makes: which Jakarta day the segmented
//  control is pointing at, what the summary card says, how `Semua` is paged and
//  grouped, and which subtotals are honest enough to show. The view below it
//  renders and taps (CONVENTIONS.md, layering).
//
//  This type reads. It never writes: no `save()`, no `ModelContext`, no
//  repository — module 04's `SaleServicing` is the whole of its surface
//  (R-05-8, 05 §7). The one write the screen can trigger is a void, and that
//  belongs to `SaleDetailViewModel`, which delegates it to module 04.
//
//  Nothing here caches an aggregate. `summary` and `groups` are rebuilt from
//  the rows on every read (R-05-3).
//

import Foundation

@MainActor
@Observable
final class HistoryViewModel {

    /// The segmented control (05 §10). Raw values stay English; only the label
    /// the operator reads is Indonesian.
    enum Scope: String, CaseIterable, Hashable {
        case today, yesterday, all

        var label: String {
            switch self {
            case .today:     return "Hari Ini"
            case .yesterday: return "Kemarin"
            case .all:       return "Semua"
            }
        }
    }

    /// 05 §8. The one paged list in the app, and only because ~18,000 rows a
    /// year makes it genuinely unbounded (foundations §8).
    static let pageSize = 100

    /// Bound to the picker. The view calls `load()` when it changes.
    var scope: Scope = .today

    /// Every row for the current scope, voided sales included. Nothing is ever
    /// filtered out of this list — hiding a void would make the ledger a lie
    /// (R-05-2).
    private(set) var sales: [Sale] = []

    /// The card above the list. Meaningless under `Semua`, where each day
    /// carries its own subtotal instead.
    private(set) var summary: DaySummary

    /// `Semua` only: one section per Jakarta day, newest day first.
    private(set) var groups: [DaySummary.Group] = []

    private(set) var canLoadMore = false
    private(set) var errorMessage: String?

    private let service: SaleServicing

    /// Injected so a test can pin "today" to a fixed instant. In the app it is
    /// `Date.init` and nothing else.
    private let now: () -> Date

    init(sales: SaleServicing, now: @escaping () -> Date = Date.init) {
        self.service = sales
        self.now = now
        self.summary = DaySummary.of([], on: now())
    }

    // MARK: - Reading

    /// The Jakarta day the current scope points at (R-05-1). `Semua` spans
    /// many; it reports today so the type always has a valid stamp.
    var day: Date {
        switch scope {
        case .today, .all: return JakartaDay.startOfDay(now())
        case .yesterday:   return JakartaDay.previousDay(now())
        }
    }

    /// `Semua` sections by day; the other two scopes are one flat list.
    var isGrouped: Bool { scope == .all }

    /// The card is a *day* summary, so it only appears on a scope that is one
    /// day. Under `Semua` an all-time total would either be wrong — it can only
    /// see the loaded window — or need an unbounded fetch that foundations §8
    /// forbids. Each section header carries the figure §3.4 actually asks for.
    var showsSummaryCard: Bool { !isGrouped }

    var isEmpty: Bool { sales.isEmpty }

    var emptyMessage: String {
        switch scope {
        case .today:     return "Belum ada transaksi hari ini"
        case .yesterday: return "Belum ada transaksi kemarin"
        case .all:       return "Belum ada transaksi"
        }
    }

    /// The oldest visible day is only half-loaded while another page exists, so
    /// its subtotal would be a partial figure presented as a day total. It is
    /// withheld until the day is complete rather than shown and quietly
    /// corrected on the next scroll (R-05-3).
    func showsSubtotal(for group: DaySummary.Group) -> Bool {
        guard canLoadMore else { return true }
        return group.id != groups.last?.id
    }

    // MARK: - Loading

    /// First page for the current scope. Called on appear and on every scope
    /// change.
    func load() {
        errorMessage = nil
        do {
            switch scope {
            case .today, .yesterday:
                let day = self.day
                sales = try service.sales(onJakartaDay: day)   // voided included
                summary = DaySummary.of(sales, on: day)        // voided excluded
                groups = []
                canLoadMore = false

            case .all:
                let page = try service.allSales(limit: Self.pageSize, offset: 0)
                sales = page
                canLoadMore = page.count == Self.pageSize
                regroup()
            }
        } catch {
            reset()
            report(error)
        }
    }

    /// 05 §8: `Semua` appends on scroll. Every other scope is one Jakarta day
    /// and is never paged.
    func loadMore() {
        guard scope == .all, canLoadMore else { return }
        errorMessage = nil
        do {
            let page = try service.allSales(limit: Self.pageSize, offset: sales.count)
            sales += page
            canLoadMore = page.count == Self.pageSize
            regroup()
        } catch {
            report(error)
        }
    }

    /// Re-reads what is already on screen, in place. Used after a void, which
    /// must refresh the list and the summary **without** collapsing a scrolled
    /// window back to page one (05 §3.3, §8).
    func refresh() {
        guard scope == .all, !sales.isEmpty else { return load() }
        errorMessage = nil
        do {
            sales = try service.allSales(limit: sales.count, offset: 0)
            regroup()
        } catch {
            reset()
            report(error)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Internals

    private func regroup() {
        groups = DaySummary.grouped(sales)
        // Under `Semua` the card is hidden, but the stamp stays valid.
        summary = DaySummary.of([], on: day)
    }

    private func reset() {
        sales = []
        groups = []
        canLoadMore = false
        summary = DaySummary.of([], on: day)   // R-05-7: zeros, never blank
    }

    private func report(_ error: Error) {
        errorMessage = (error as? POSError)?.message
            ?? POSError.persistenceFailed(String(describing: error)).message
    }
}

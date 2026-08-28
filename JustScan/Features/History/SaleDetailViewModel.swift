//
//  SaleDetailViewModel.swift
//  JustScan
//
//  What the sale detail screen shows, and the one thing it can do.
//
//  It exists because a View may not call a Service (CONVENTIONS.md), and
//  **Batalkan** is a service call — the same reason 03 has a
//  `ProductDetailViewModel` and 02 a `ContactFieldViewModel`. The void itself
//  belongs to module 04 (R-04-12..15): this type presents it and implements
//  none of it.
//
//  Every figure on this screen comes off `SaleLine`'s snapshots. There is no
//  `CatalogueServicing` here and no `ProductRepository`, so a live price lookup
//  is not something this screen could do by accident (R-05-4).
//

import Foundation

@MainActor
@Observable
final class SaleDetailViewModel {
    let sale: Sale

    private(set) var errorMessage: String?

    /// Flips once, when this screen's own void succeeds. Drives the refresh of
    /// the list behind it; the screen itself stays put (05 §3.3).
    private(set) var didVoid = false

    private let service: SaleServicing

    init(sale: Sale, sales: SaleServicing) {
        self.sale = sale
        self.service = sales
    }

    // MARK: - Reading

    /// R-05-4. `nameSnapshot` and `unitPriceRp`, never a live `Product`.
    ///
    /// Sorted explicitly because foundations §6 bans ordered relationships, and
    /// `SaleLine` carries no ordinal and no `createdAt` — left alone the order
    /// is whatever the fetch happened to produce. Name first, then `id` so two
    /// lines that somehow share a name still order the same way twice.
    var lines: [SaleLine] {
        (sale.lines ?? []).sorted {
            let byName = $0.nameSnapshot.localizedStandardCompare($1.nameSnapshot)
            if byName != .orderedSame { return byName == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var isVoided: Bool { sale.status == .voided }

    /// A voided sale gets a banner and no void action (05 §3.2). The service
    /// still throws `saleAlreadyVoided` behind it — the hidden button is a
    /// courtesy, not the rule (R-04-12).
    var canVoid: Bool { !isVoided }

    /// Cash received and change are shown for cash sales only. For QRIS both
    /// are `nil` meaning "not applicable", which is not the same as `0`
    /// (R-04-10, D-08).
    var showsCashDetail: Bool { sale.method == .cash }

    var customer: ContactRef? { sale.customer }

    // MARK: - The one write, delegated

    /// Hands the reason to module 04 and does nothing else with it. Trimming,
    /// the length rule, the stock reversal, and the single commit are all
    /// `SaleService.void` (R-04-13, R-04-14, R-04-15).
    func void(reason: String) {
        errorMessage = nil
        do {
            try service.void(sale, reason: reason)
            didVoid = true
        } catch {
            report(error)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func report(_ error: Error) {
        errorMessage = (error as? POSError)?.message
            ?? POSError.persistenceFailed(String(describing: error)).message
    }
}

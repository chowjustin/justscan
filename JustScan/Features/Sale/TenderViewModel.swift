//
//  TenderViewModel.swift
//  JustScan
//
//  The tender sheet's arithmetic, so the sheet itself does none (a View never
//  does money arithmetic — CONVENTIONS.md).
//
//  It decides what the operator may confirm and what the shortfall reads; it
//  does **not** commit. `SaleService.complete` is still the guard that matters
//  — this type only keeps the operator from tapping a button that would throw
//  (04 §3).
//

import Foundation

@MainActor
@Observable
final class TenderViewModel {
    let totalRp: Int

    /// Tunai is preselected (04 §3.2).
    var method: PaymentMethod = .cash

    /// Bound to the cash field. A string rather than an `Int?` so a
    /// half-typed amount is representable; only digits survive parsing.
    var cashText: String = ""

    init(totalRp: Int) {
        self.totalRp = totalRp
    }

    /// R-04-10. QRIS is exact by construction, so there is no amount to read —
    /// nil, never 0.
    var cashReceivedRp: Int? {
        guard method == .cash else { return nil }
        let digits = cashText.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    /// R-04-9, in ascending order, with the exact-amount chip handled
    /// separately by the sheet.
    var quickPicks: [Int] {
        method == .cash ? CashQuickPicks.amounts(forTotalRp: totalRp) : []
    }

    /// What is still owed, or nil when nothing is. Shown as "Kurang Rp 4.000"
    /// (04 §11).
    var shortfallRp: Int? {
        guard method == .cash else { return nil }
        let shortfall = totalRp - (cashReceivedRp ?? 0)
        return shortfall > 0 ? shortfall : nil
    }

    /// R-04-8. Nil for QRIS — "not applicable" is not the same answer as zero.
    var changeRp: Int? {
        guard method == .cash, let received = cashReceivedRp, received >= totalRp
        else { return nil }
        return received - totalRp
    }

    /// Cash below the total keeps confirm disabled; `insufficientCash` is still
    /// the service-level guard behind it (04 §3.4).
    var canConfirm: Bool {
        method == .qris || shortfallRp == nil
    }

    /// Tapping a chip fills the field.
    func select(amountRp: Int) {
        cashText = String(amountRp)
    }

    /// The "Pas" chip — the exact amount, which R-04-9 keeps out of the
    /// rounded-up list.
    func selectExactAmount() {
        select(amountRp: totalRp)
    }
}

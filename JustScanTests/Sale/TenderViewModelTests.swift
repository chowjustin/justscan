//
//  TenderViewModelTests.swift
//  JustScanTests
//
//  R-04-8, R-04-9 and R-04-10 as the tender sheet presents them: what the
//  operator may confirm, what the shortfall reads, and what "no change due"
//  looks like next to "not applicable".
//
//  The service still owns every one of these rules. These tests pin the
//  *display* decision, which is the ViewModel's, so the sheet itself does no
//  arithmetic (CONVENTIONS.md).
//

import Foundation
import Testing
@testable import JustScan

@MainActor
struct TenderViewModelTests {

    @Test("04 §3.2: Tunai is preselected and nothing is confirmable until it covers the total")
    func test_cashIsPreselected() {
        let model = TenderViewModel(totalRp: 29_000)

        #expect(model.method == .cash)
        #expect(model.cashText.isEmpty)
        #expect(model.cashReceivedRp == nil)
        #expect(!model.canConfirm)
        #expect(model.shortfallRp == 29_000)
    }

    @Test("R-04-8/04 §11: 25.000 against 29.000 shows a 4.000 shortfall and stays disabled")
    func test_R0408_shortfallIsExact() {
        let model = TenderViewModel(totalRp: 29_000)
        model.cashText = "25000"

        #expect(model.shortfallRp == 4_000)
        #expect(model.changeRp == nil)
        #expect(!model.canConfirm)
        #expect(Rp.format(model.shortfallRp ?? 0) == "Rp 4.000")
    }

    @Test("R-04-8/AC-04-5: 50.000 against 29.000 shows 21.000 change and enables confirm")
    func test_R0408_changeIsExact() {
        let model = TenderViewModel(totalRp: 29_000)
        model.cashText = "50000"

        #expect(model.cashReceivedRp == 50_000)
        #expect(model.shortfallRp == nil)
        #expect(model.changeRp == 21_000)
        #expect(model.canConfirm)
    }

    @Test("R-04-8/04 §8: cash exactly equal to the total is confirmable with 0 change")
    func test_R0408_exactCashGivesZeroChange() {
        let model = TenderViewModel(totalRp: 29_000)
        model.selectExactAmount()

        #expect(model.cashText == "29000")
        #expect(model.changeRp == 0)
        #expect(model.shortfallRp == nil)
        #expect(model.canConfirm)
    }

    @Test("R-04-10: QRIS needs no amount, offers no chips, and reports nil for both figures")
    func test_R0410_qrisIsExactByConstruction() {
        let model = TenderViewModel(totalRp: 29_000)
        model.cashText = "50000"          // typed before switching method
        model.method = .qris

        #expect(model.cashReceivedRp == nil)
        #expect(model.changeRp == nil)
        #expect(model.shortfallRp == nil)
        #expect(model.quickPicks.isEmpty)
        #expect(model.canConfirm)
    }

    @Test("R-04-9/04 §11: the chips for 29.000 are the four round-ups, and tapping one fills the field")
    func test_R0409_quickPicksFillTheField() {
        let model = TenderViewModel(totalRp: 29_000)

        #expect(model.quickPicks == [30_000, 40_000, 50_000, 100_000])

        model.select(amountRp: 50_000)
        #expect(model.cashText == "50000")
        #expect(model.changeRp == 21_000)
    }

    @Test("the cash field ignores anything that is not a digit")
    func test_cashFieldParsesDigitsOnly() {
        let model = TenderViewModel(totalRp: 29_000)

        model.cashText = "Rp 50.000"
        #expect(model.cashReceivedRp == 50_000)

        model.cashText = "abc"
        #expect(model.cashReceivedRp == nil)
        #expect(!model.canConfirm)
    }
}

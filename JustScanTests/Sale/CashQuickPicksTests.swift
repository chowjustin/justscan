//
//  CashQuickPicksTests.swift
//  JustScanTests
//
//  R-04-9. The §11 worked example is the first test and its numbers are exact:
//  `29.000 → 30.000 · 40.000 · 50.000 · 100.000`, plus the separate "Pas" chip
//  the view adds.
//

import Foundation
import Testing
@testable import JustScan

struct CashQuickPicksTests {

    @Test("R-04-9/04 §11: 29.000 offers 30.000, 40.000, 50.000, 100.000")
    func test_R0409_theWorkedExample() {
        #expect(CashQuickPicks.amounts(forTotalRp: 29_000)
                == [30_000, 40_000, 50_000, 100_000])
    }

    @Test("R-04-9: the 5k and 10k round-ups collapse to one chip")
    func test_R0409_duplicatesAreRemoved() {
        // 29.000 rounds up to 30.000 under both 5.000 and 10.000.
        let amounts = CashQuickPicks.amounts(forTotalRp: 29_000)
        #expect(amounts.count == Set(amounts).count)
        #expect(amounts.filter { $0 == 30_000 }.count == 1)
    }

    @Test("R-04-9: a chip equal to the total is excluded — that is what Pas is for")
    func test_R0409_exactAmountIsNeverAChip() {
        // 30.000 is already a multiple of 5.000 and of 10.000.
        #expect(CashQuickPicks.amounts(forTotalRp: 30_000) == [40_000, 50_000, 100_000])
        #expect(!CashQuickPicks.amounts(forTotalRp: 30_000).contains(30_000))

        // 100.000 is a multiple of every denomination, so nothing survives.
        #expect(CashQuickPicks.amounts(forTotalRp: 100_000).isEmpty)
    }

    @Test("R-04-9: chips are ascending")
    func test_R0409_chipsAreAscending() {
        for total in [1_000, 4_999, 12_500, 29_000, 63_400, 99_999] {
            let amounts = CashQuickPicks.amounts(forTotalRp: total)
            #expect(amounts == amounts.sorted())
        }
    }

    @Test("R-04-9: every chip is a round-up of the total, never below it")
    func test_R0409_everyChipCoversTheTotal() {
        for total in [500, 3_500, 12_000, 29_000, 45_000, 87_650, 150_000] {
            for amount in CashQuickPicks.amounts(forTotalRp: total) {
                #expect(amount > total)
                #expect(CashQuickPicks.denominations.contains { amount % $0 == 0 })
            }
        }
    }

    @Test("R-04-9: a total above 100.000 still offers the next 100.000")
    func test_R0409_totalsAboveTheLargestNote() {
        // 150.000 → 5k/10k/50k all give 150.000 (excluded), 20k gives 160.000,
        // 100k gives 200.000.
        #expect(CashQuickPicks.amounts(forTotalRp: 150_000) == [160_000, 200_000])
        #expect(CashQuickPicks.amounts(forTotalRp: 123_000)
                == [125_000, 130_000, 140_000, 150_000, 200_000])
    }

    @Test("R-04-9: a total of zero offers nothing — the cart guard catches it first")
    func test_R0409_zeroTotalOffersNothing() {
        #expect(CashQuickPicks.amounts(forTotalRp: 0).isEmpty)
        #expect(CashQuickPicks.amounts(forTotalRp: -1).isEmpty)
    }

    @Test("R-04-9: a one-rupiah total rounds up to every denomination")
    func test_R0409_smallestTotal() {
        #expect(CashQuickPicks.amounts(forTotalRp: 1)
                == [5_000, 10_000, 20_000, 50_000, 100_000])
    }
}

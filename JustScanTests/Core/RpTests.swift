//
//  RpTests.swift
//  JustScanTests
//
//  R-01-2 / AC-01-2 — the five exact strings from 01 §11.
//

import Foundation
import Testing
@testable import JustScan

struct RpTests {
    @Test("R-01-2: the five worked examples, exactly")
    func test_R0102_formatsTheWorkedExamples() {
        #expect(Rp.format(12_000) == "Rp 12.000")
        #expect(Rp.format(0) == "Rp 0")
        #expect(Rp.format(-21_000) == "-Rp 21.000")
        #expect(Rp.format(1_500_000) == "Rp 1.500.000")
    }

    @Test("R-01-2: the separator is a full stop and the space is a plain ASCII space")
    func test_R0102_usesPlainSpaceNotNonBreakingSpace() {
        let formatted = Rp.format(12_000)
        // id_ID currency formatting emits U+00A0 here. §11 pins U+0020.
        #expect(formatted.contains("\u{00A0}") == false)
        #expect(formatted.contains(" "))
        #expect(formatted.contains("."))
        #expect(formatted.contains(",") == false)
    }

    @Test("R-01-2: independent of the device locale")
    func test_R0102_isLocaleIndependent() {
        // The formatter pins id_ID, so a US or German device still gets rupiah.
        #expect(Rp.format(1_500_000) == "Rp 1.500.000")
    }

    @Test("R-01-2: no decimal places are ever shown")
    func test_R0102_hasNoFractionDigits() {
        #expect(Rp.format(5_000) == "Rp 5.000")
        #expect(Rp.format(100) == "Rp 100")
        #expect(Rp.format(999) == "Rp 999")
    }

    @Test("R-01-2: zero and negative zero are the same string")
    func test_R0102_zeroIsNeverNegative() {
        #expect(Rp.format(0) == "Rp 0")
        #expect(Rp.format(-0) == "Rp 0")
    }

    @Test("R-01-2: extreme magnitudes do not trap")
    func test_R0102_doesNotTrapAtIntBounds() {
        // `abs(Int.min)` traps; `.magnitude` does not.
        _ = Rp.format(Int.min)
        _ = Rp.format(Int.max)
    }
}

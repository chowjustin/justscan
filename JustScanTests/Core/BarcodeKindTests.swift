//
//  BarcodeKindTests.swift
//  JustScanTests
//
//  R-01-8 / AC-01-3 — the five exact classifications from 01 §11, plus the
//  digits-only rulings recorded alongside them.
//

import Foundation
import Testing
@testable import JustScan

struct BarcodeKindTests {
    @Test("R-01-8: the five worked examples, exactly")
    func test_R0108_classifiesTheWorkedExamples() {
        #expect(BarcodeKind.of("8992775311011") == .gtin)          // 13 digits, prefix 899
        #expect(BarcodeKind.of("2011234501234") == .internalCode)  // prefix 20 — variable weight
        #expect(BarcodeKind.of("0212345000129") == .internalCode)  // prefix 02 — in-store
        #expect(BarcodeKind.of("12345678") == .gtin)               // 8 digits, EAN-8
        #expect(BarcodeKind.of("ABC-123") == .unknown)
    }

    @Test("R-01-8: the whole 20–29 prefix band is an internal code")
    func test_R0108_coversTheFullInternalPrefixBand() {
        for prefix in 20...29 {
            let code = "\(prefix)11234501234".prefix(13)
            #expect(BarcodeKind.of(String(code)) == .internalCode, "prefix \(prefix)")
        }
    }

    @Test("R-01-8: a prefix match on non-numeric input is unknown, not internal")
    func test_R0108_requiresAllDigits() {
        #expect(BarcodeKind.of("02ABC") == .unknown)
        #expect(BarcodeKind.of("2011234501AB") == .unknown)
        #expect(BarcodeKind.of("8992775 11011") == .unknown)
    }

    @Test("R-01-8: only 8, 12, or 13 digits qualify")
    func test_R0108_acceptsOnlyGTINLengths() {
        #expect(BarcodeKind.of("20") == .unknown)
        #expect(BarcodeKind.of("123456") == .unknown)          // the accepted UPC-E gap
        #expect(BarcodeKind.of("1234567") == .unknown)
        #expect(BarcodeKind.of("123456789012") == .gtin)       // 12, UPC-A
        #expect(BarcodeKind.of("12345678901234") == .unknown)  // 14
    }

    @Test("R-01-8: empty and whitespace input is unknown")
    func test_R0108_handlesEmptyInput() {
        #expect(BarcodeKind.of("") == .unknown)
        #expect(BarcodeKind.of("   ") == .unknown)
    }

    @Test("R-01-8: surrounding whitespace is trimmed before classifying")
    func test_R0108_trimsBeforeClassifying() {
        #expect(BarcodeKind.of(" 8992775311011\n") == .gtin)
    }

    @Test("R-01-8: non-ASCII digit forms are not barcodes")
    func test_R0108_rejectsNonASCIIDigits() {
        // Arabic-Indic digits satisfy `Character.isNumber` but no scanner emits them.
        #expect(BarcodeKind.of("١٢٣٤٥٦٧٨") == .unknown)
    }
}

//
//  ScannerContractTests.swift
//  JustScanTests
//
//  AC-01-4 and AC-01-5 describe camera-denied and operator-cancel, both of
//  which need a real device and a human. These tests pin the *contract* every
//  caller in modules 03 and 04 is written against; the device path is a written
//  exemption in PROGRESS.md.
//

import Foundation
import Testing
@testable import JustScan

struct ScannerContractTests {
    @Test("AC-01-4: an unavailable scanner throws scannerUnavailable and nothing else")
    func test_AC0104_throwsScannerUnavailable() async {
        let scanner = FakeScannerService(outcome: .unavailable)
        await #expect(throws: POSError.scannerUnavailable) {
            _ = try await scanner.scan()
        }
    }

    @Test("AC-01-5: cancelling returns nil and throws nothing")
    func test_AC0105_cancelReturnsNilAndDoesNotThrow() async throws {
        let scanner = FakeScannerService(outcome: .cancelled)
        let result = try await scanner.scan()
        #expect(result == nil)
    }

    @Test("A successful scan returns the code")
    func test_scannerReturnsTheCode() async throws {
        let scanner = FakeScannerService(outcome: .code("8992775311011"))
        #expect(try await scanner.scan() == "8992775311011")
    }

    @Test("A scanned code flows into BarcodeKind unchanged")
    func test_scannedCodeClassifiesEndToEnd() async throws {
        let scanner = FakeScannerService(outcome: .code("2011234501234"))
        let code = try #require(try await scanner.scan())
        #expect(BarcodeKind.of(code) == .internalCode)
    }
}

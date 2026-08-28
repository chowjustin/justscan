//
//  FakeScannerService.swift
//  JustScanTests
//
//  Stands in for the camera. The real permission and cancel paths need a device
//  and a human; this proves the *contract* every caller depends on.
//

import Foundation
@testable import JustScan

final class FakeScannerService: ScannerServicing, @unchecked Sendable {
    enum Outcome {
        case code(String)
        case cancelled
        case unavailable
    }

    var outcome: Outcome
    private(set) var scanCount = 0

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func scan() async throws -> String? {
        scanCount += 1
        switch outcome {
        case .code(let value):
            return value
        case .cancelled:
            return nil
        case .unavailable:
            throw POSError.scannerUnavailable
        }
    }
}

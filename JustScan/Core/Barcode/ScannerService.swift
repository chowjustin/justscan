//
//  ScannerService.swift
//  JustScan
//
//  The scanner wrapped as a plain Swift service. Callers await a string; they
//  never learn that VisionKit exists.
//
//  A scan is the primary gesture of this app, so the contract is deliberately
//  narrow: one code, or nil because the operator changed their mind, or
//  `scannerUnavailable`. Nothing else.
//

import AVFoundation
import Foundation
import UIKit
import VisionKit

protocol ScannerServicing {
    func scan() async throws -> String?    // nil == operator cancelled
}

@MainActor
final class ScannerService: ScannerServicing {
    /// Guards the "scan while a scan is presenting" case (01 §8). Scans do not
    /// queue — the second call returns nil at once rather than stacking sheets.
    private var isPresenting = false

    func scan() async throws -> String? {
        guard !isPresenting else { return nil }

        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable
        else { throw POSError.scannerUnavailable }

        guard await Self.hasCameraAccess() else {
            throw POSError.scannerUnavailable
        }

        guard let presenter = Self.topViewController() else {
            throw POSError.scannerUnavailable
        }

        isPresenting = true
        defer { isPresenting = false }

        let raw = await BarcodeScanPresenter.present(from: presenter)

        // A scanned string may arrive with whitespace or a trailing newline (01 §8).
        guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty
        else { return nil }

        return code
    }

    /// Camera permission. A denied or restricted device is `scannerUnavailable`,
    /// never a crash — every screen that scans also has a manual path (01 §8).
    private static func hasCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

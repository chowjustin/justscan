//
//  BarcodeScanPresenter.swift
//  JustScan
//
//  The DataScannerViewController wrapper. Internal to Core/Barcode — no feature
//  module imports VisionKit, and nothing outside ScannerService calls this.
//
//  STRUCTURE.md names this file `DataScannerView.swift` and describes a
//  `UIViewControllerRepresentable`. It is a presenter instead: a representable
//  would make the *view* own scanner lifetime and results, and the exported
//  contract is `ScannerServicing.scan() async throws -> String?` — a service
//  call a ViewModel awaits. Recorded in PROGRESS.md under Deviations.
//

import Foundation
import UIKit
import Vision
import VisionKit

@MainActor
enum BarcodeScanPresenter {
    /// Presents the scanner and resolves with the first code read, or nil if the
    /// operator cancelled. Cancelling is not an error (01 §3).
    static func present(from presenter: UIViewController) async -> String? {
        await withCheckedContinuation { continuation in
            let session = BarcodeScanSession(continuation: continuation)
            session.present(from: presenter)
        }
    }
}

@MainActor
private final class BarcodeScanSession: NSObject, DataScannerViewControllerDelegate {
    /// Exactly these four (R-01-6). Any other symbology is never recognised, so
    /// it is never reported — the rule is enforced by not asking for it.
    private static let symbologies: [VNBarcodeSymbology] = [
        .ean13, .ean8, .upce, .code128
    ]

    private var continuation: CheckedContinuation<String?, Never>?
    private var scanner: DataScannerViewController?
    /// Kept alive for the lifetime of the sheet — `DataScannerViewController`
    /// holds its delegate weakly.
    private var selfReference: BarcodeScanSession?

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
        super.init()
        self.selfReference = self
    }

    func present(from presenter: UIViewController) {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        scanner.title = "Pindai Barcode"
        scanner.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.finish(with: nil) }
        )
        self.scanner = scanner

        // A navigation bar so Cancel is always visible — never a modal the
        // operator can be trapped in (01 §10).
        let navigation = UINavigationController(rootViewController: scanner)
        navigation.modalPresentationStyle = .fullScreen

        presenter.present(navigation, animated: true) {
            try? scanner.startScanning()
        }
    }

    // MARK: - DataScannerViewControllerDelegate

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        guard let code = addedItems.compactMap(Self.payload).first else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        finish(with: code)
    }

    func dataScannerDidZoom(_ dataScanner: DataScannerViewController) {}

    // MARK: - Teardown

    private static func payload(_ item: RecognizedItem) -> String? {
        guard case .barcode(let barcode) = item else { return nil }
        return barcode.payloadStringValue
    }

    /// Resolves the continuation exactly once and dismisses.
    private func finish(with code: String?) {
        guard let continuation else { return }
        self.continuation = nil

        scanner?.stopScanning()
        scanner?.presentingViewController?.dismiss(animated: true)
        scanner = nil

        continuation.resume(returning: code)
        selfReference = nil
    }
}

//
//  ContactPickerPresenter.swift
//  JustScan
//
//  The `CNContactPickerViewController` wrapper. Internal to Core/Contacts —
//  nothing outside `ContactService` calls it, and no feature module imports
//  Contacts (AC-02-7).
//
//  STRUCTURE.md names this file `ContactPickerView.swift` and implies a
//  `UIViewControllerRepresentable`. It is a presenter instead, for the same
//  reason `BarcodeScanPresenter` is: the exported contract is
//  `pick() async -> ContactRef?`, a value a ViewModel awaits. A representable
//  would put picker lifetime and results in the *view*, inverting the layering
//  rule. Recorded in PROGRESS.md under Deviations.
//

import Contacts
import ContactsUI
import Foundation
import UIKit

@MainActor
enum ContactPickerPresenter {
    /// Presents the system picker and resolves with the chosen contact, or nil
    /// if the operator cancelled. Cancelling is not an error (02 §3, R-02-7).
    ///
    /// No authorization prompt appears on this path: the picker runs
    /// out-of-process, so the operator picking a contact **is** the consent.
    static func present() async -> CNContact? {
        guard let presenter = topViewController() else { return nil }
        return await withCheckedContinuation { continuation in
            let session = ContactPickSession(continuation: continuation)
            session.present(from: presenter)
        }
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
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

@MainActor
private final class ContactPickSession: NSObject, CNContactPickerDelegate {
    private var continuation: CheckedContinuation<CNContact?, Never>?
    /// Kept alive for the lifetime of the sheet — the picker holds its delegate
    /// weakly.
    private var selfReference: ContactPickSession?

    init(continuation: CheckedContinuation<CNContact?, Never>) {
        self.continuation = continuation
        super.init()
        self.selfReference = self
    }

    func present(from presenter: UIViewController) {
        let picker = CNContactPickerViewController()
        picker.delegate = self
        // Only `contactPicker(_:didSelect contact:)` is implemented, so a tap
        // selects the whole contact instead of drilling into a property. No
        // property keys are displayed, which is also how R-02-6 stays true of
        // the UI and not just of the fetch.
        picker.displayedPropertyKeys = []
        presenter.present(picker, animated: true)
    }

    // MARK: - CNContactPickerDelegate

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        finish(with: contact)
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        finish(with: nil)
    }

    /// Resolves the continuation exactly once. The picker dismisses itself on
    /// both paths, so there is no dismiss call here to double up on.
    private func finish(with contact: CNContact?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: contact)
        selfReference = nil
    }
}

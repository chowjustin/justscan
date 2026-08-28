//
//  ContactService.swift
//  JustScan
//
//  Module 02's whole exported surface (02 §7). Turns "who is this supplier" into
//  two taps on the phone's own Contacts, and guarantees the name stays readable
//  after the contact is renamed, merged, or deleted.
//
//  This module persists nothing. It returns a value; the calling module stores
//  it as two columns (02 §1, R-02-1).
//

import Contacts
import Foundation

protocol ContactServicing {
    @MainActor func pick() async -> ContactRef?              // nil == cancelled
    func resolve(id: String) async throws -> ContactRef?     // nil == gone
    var authorizationStatus: ContactAccess { get }
}

final class ContactService: ContactServicing {
    private let store = CNContactStore()

    /// R-02-6: exactly these three, and never a phone number, email, or address.
    /// `organizationName` is here because R-02-3's fallback chain cannot run
    /// without it — the formatter descriptor alone does not include it.
    private static let keysToFetch: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactOrganizationNameKey as CNKeyDescriptor
    ]

    var authorizationStatus: ContactAccess {
        Self.access(for: CNContactStore.authorizationStatus(for: .contacts))
    }

    /// The only translation between the framework's status and this app's.
    private static func access(for status: CNAuthorizationStatus) -> ContactAccess {
        switch status {
        case .authorized:            return .granted
        case .notDetermined:         return .notDetermined
        case .denied, .restricted:   return .denied

        // iOS 18's limited access. A lookup is attempted and a contact outside
        // the granted set simply reads as gone, which is the state `resolve`
        // already returns nil for — so it maps to `.granted`, not `.denied`
        // (R-02-4, and `ContactAccess.granted`'s own doc comment).
        case .limited:               return .granted

        @unknown default:            return .granted
        }
    }

    /// The system picker. Cannot throw and cannot prompt — it runs
    /// out-of-process (02 §3). Cancelling returns nil, which every caller must
    /// treat as ordinary (R-02-7).
    @MainActor
    func pick() async -> ContactRef? {
        guard let contact = await ContactPickerPresenter.present() else { return nil }
        return Self.makeRef(from: contact)
    }

    /// A live lookup of a stored identifier. Unlike `pick()`, this path does
    /// require authorization (02 §3).
    ///
    /// Returns nil when the contact is gone — deleted, merged away, or simply
    /// never real, which is the case for the DEBUG seed's synthetic
    /// `"seed-toko-grosir-budi"` identifiers (foundations §9). That is a normal
    /// outcome, not an error (R-02-4). Only a refused permission throws.
    func resolve(id: String) async throws -> ContactRef? {
        guard await hasAccess() else { throw POSError.contactAccessDenied }

        do {
            let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: Self.keysToFetch)
            return Self.makeRef(from: contact)
        } catch let error as CNError where error.code == .authorizationDenied {
            // Permission revoked between the check above and the fetch (02 §8).
            throw POSError.contactAccessDenied
        } catch {
            // `recordDoesNotExist` and every other read failure mean the same
            // thing to this app: the contact is gone, and the caller's stored
            // snapshot is what renders (R-02-4).
            return nil
        }
    }

    private func hasAccess() async -> Bool {
        switch authorizationStatus {
        case .granted:
            return true
        case .notDetermined:
            // An explicit call to `resolve` is a request to look, so this asks.
            // `ContactFieldViewModel` never reaches here — it gates on
            // `.granted` precisely so a read-only screen cannot raise a prompt.
            return (try? await store.requestAccess(for: .contacts)) ?? false
        case .denied:
            return false
        }
    }

    /// The only place a `CNContact` becomes a `ContactRef`. Name and identifier
    /// only — nothing else is read (02 §1).
    private static func makeRef(from contact: CNContact) -> ContactRef {
        let formatterKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        let fullName = contact.areKeysAvailable([formatterKeys])
            ? CNContactFormatter.string(from: contact, style: .fullName)
            : nil
        let organization = contact.isKeyAvailable(CNContactOrganizationNameKey)
            ? contact.organizationName
            : nil

        return ContactRef(
            id: contact.identifier,
            name: ContactRef.snapshotName(fullName: fullName, organizationName: organization)
        )
    }
}

//
//  ContactFieldViewModel.swift
//  JustScan
//
//  `ContactField` needs to know whether a stored contact still exists, and a
//  View may not call a Service (CONVENTIONS.md, layering). This is that one
//  arrow: View → ViewModel → ContactServicing.
//
//  The host module owns the instance. `ProductFormViewModel` (03) holds one for
//  the supplier, `TenderViewModel` (04) holds one for the customer, and each
//  reads `ref` when it saves. That is how two columns land on the host entity
//  without this module ever touching persistence (02 §1).
//

import Foundation

@MainActor
@Observable
final class ContactFieldViewModel {
    /// The three states of 02 §10, derived rather than stored, so `ref` and the
    /// rendered state can never disagree.
    enum State: Equatable {
        case empty
        case filled(ContactRef)
        case gone(name: String)
    }

    /// What the host stores. Both host columns come from here, or both are nil
    /// (R-02-1, R-02-5).
    private(set) var ref: ContactRef?

    /// Set only by `checkResolvable()`. A missing contact is a display state,
    /// never an error (R-02-4).
    private(set) var isMissing = false

    private let contacts: ContactServicing

    init(contacts: ContactServicing, ref: ContactRef? = nil) {
        self.contacts = contacts
        self.ref = ref
    }

    var state: State {
        guard let ref else { return .empty }
        return isMissing ? .gone(name: ref.name) : .filled(ref)
    }

    /// Presents the system picker. Cancelling leaves the current value
    /// untouched — it is not a detach (02 §8).
    func pick() async {
        guard let picked = await contacts.pick() else { return }
        ref = picked
        isMissing = false
    }

    /// Clears both host columns together (R-02-5). Available in the `gone` state
    /// too, so a supplier whose contact was deleted can still be re-picked.
    func detach() {
        ref = nil
        isMissing = false
    }

    /// Decides between `filled` and `gone`.
    ///
    /// Only runs when access is **already** granted. Resolving is a nicety on a
    /// read-only screen, and asking for the address book because the operator
    /// opened a product would be an ambush — the picker never prompts, so this
    /// would be the app's only Contacts prompt, raised at its least explicable
    /// moment. Without access the name simply renders as normal, which is what
    /// R-02-2 and D-11 promise.
    func checkResolvable() async {
        guard let ref, contacts.authorizationStatus == .granted else { return }

        do {
            isMissing = try await contacts.resolve(id: ref.id) == nil
        } catch {
            // Permission revoked while backgrounded (02 §8). The snapshot still
            // renders; the app never loses data over a permission change.
            isMissing = true
        }
    }
}

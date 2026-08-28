//
//  ContactFieldViewModelTests.swift
//  JustScanTests
//
//  `ContactField`'s three states (02 §10) are decided here, not in the view, so
//  this is where they are tested. Per CONVENTIONS.md we do not test SwiftUI
//  views — we test the ViewModel that tells them what to render.
//

import Foundation
import Testing
@testable import JustScan

@MainActor
struct ContactFieldViewModelTests {
    private static let budi = ContactRef(id: "ABC-123", name: "Budi Santoso")

    // MARK: - Attaching and detaching

    @Test("Picking attaches both fields at once")
    func test_R0201_pickAttachesTheWholeRef() async {
        let contacts = FakeContactService(pick: .contact(Self.budi))
        let viewModel = ContactFieldViewModel(contacts: contacts)

        #expect(viewModel.state == .empty)
        await viewModel.pick()

        #expect(viewModel.ref == Self.budi)
        #expect(viewModel.state == .filled(Self.budi))
    }

    @Test("R-02-5: detaching clears both fields together")
    func test_R0205_detachClearsBothFields() {
        let viewModel = ContactFieldViewModel(
            contacts: FakeContactService(),
            ref: Self.budi
        )

        viewModel.detach()

        #expect(viewModel.ref == nil)
        #expect(viewModel.state == .empty)
    }

    @Test("R-02-7 / 02 §8: cancelling the picker leaves the current value untouched")
    func test_R0207_cancellingLeavesTheValueUntouched() async {
        let contacts = FakeContactService(pick: .cancelled)
        let viewModel = ContactFieldViewModel(contacts: contacts, ref: Self.budi)

        await viewModel.pick()

        #expect(viewModel.ref == Self.budi)
        #expect(contacts.pickCount == 1)
    }

    @Test("R-02-7: an empty field is a valid resting state — nothing blocks on a contact")
    func test_R0207_emptyIsATerminalState() async {
        let viewModel = ContactFieldViewModel(contacts: FakeContactService(pick: .cancelled))
        await viewModel.pick()
        #expect(viewModel.ref == nil)
        #expect(viewModel.state == .empty)
    }

    // MARK: - The gone state

    @Test("AC-02-3: a contact that no longer exists still renders its stored name, with no error")
    func test_AC0203_missingContactRendersTheSnapshot() async {
        let contacts = FakeContactService(resolve: .gone, access: .granted)
        let viewModel = ContactFieldViewModel(contacts: contacts, ref: Self.budi)

        await viewModel.checkResolvable()

        #expect(viewModel.state == .gone(name: "Budi Santoso"))
        #expect(viewModel.ref == Self.budi)   // the product's history is intact
    }

    @Test("AC-02-5: permission revoked mid-session still renders the snapshot, never an error")
    func test_AC0205_revokedPermissionStillRendersTheSnapshot() async {
        // 02 §8: the status said granted, then Settings changed while the app
        // was backgrounded and the fetch threw.
        let contacts = FakeContactService(resolve: .denied, access: .granted)
        let viewModel = ContactFieldViewModel(contacts: contacts, ref: Self.budi)

        await viewModel.checkResolvable()

        #expect(viewModel.state == .gone(name: "Budi Santoso"))
        #expect(viewModel.ref == Self.budi)
    }

    @Test("A live contact stays in the filled state")
    func test_liveContactStaysFilled() async {
        let contacts = FakeContactService(resolve: .found(Self.budi), access: .granted)
        let viewModel = ContactFieldViewModel(contacts: contacts, ref: Self.budi)

        await viewModel.checkResolvable()

        #expect(viewModel.state == .filled(Self.budi))
    }

    @Test("R-02-2: resolving a renamed contact does not rewrite the snapshot")
    func test_R0202_resolveNeverRefreshesTheSnapshot() async {
        let contacts = FakeContactService(
            resolve: .found(ContactRef(id: "ABC-123", name: "Budi Grosir")),
            access: .granted
        )
        let viewModel = ContactFieldViewModel(contacts: contacts, ref: Self.budi)

        await viewModel.checkResolvable()

        #expect(viewModel.ref?.name == "Budi Santoso")
        #expect(viewModel.state == .filled(Self.budi))
    }

    // MARK: - Never ambush the operator with a permission prompt

    @Test("Without granted access the field never resolves, and renders normally")
    func test_deniedAccessNeverResolves() async {
        let contacts = FakeContactService(resolve: .denied, access: .denied)
        let viewModel = ContactFieldViewModel(contacts: contacts, ref: Self.budi)

        await viewModel.checkResolvable()

        #expect(contacts.resolveCount == 0)
        #expect(viewModel.state == .filled(Self.budi))
    }

    @Test("An unasked permission is never asked for by a read-only screen")
    func test_notDeterminedAccessNeverResolves() async {
        let contacts = FakeContactService(resolve: .gone, access: .notDetermined)
        let viewModel = ContactFieldViewModel(contacts: contacts, ref: Self.budi)

        await viewModel.checkResolvable()

        #expect(contacts.resolveCount == 0)
        #expect(viewModel.state == .filled(Self.budi))
    }

    @Test("An empty field never resolves anything")
    func test_emptyFieldNeverResolves() async {
        let contacts = FakeContactService(access: .granted)
        let viewModel = ContactFieldViewModel(contacts: contacts)

        await viewModel.checkResolvable()

        #expect(contacts.resolveCount == 0)
        #expect(viewModel.state == .empty)
    }
}

//
//  ContactServiceContractTests.swift
//  JustScanTests
//
//  The §7 contract every caller in 03 and 04 is written against. The device
//  paths — a real picker, a real permission dialog — are written exemptions in
//  PROGRESS.md; these pin the behaviour those paths must produce.
//

import Foundation
import Testing
@testable import JustScan

@MainActor
struct ContactServiceContractTests {
    private static let budi = ContactRef(id: "ABC-123", name: "Budi Santoso")

    @Test("AC-02-1: picking a contact returns a ref whose name is non-empty")
    func test_AC0201_pickReturnsNonEmptyName() async {
        let contacts = FakeContactService(pick: .contact(Self.budi))
        let ref = await contacts.pick()
        #expect(ref?.name.isEmpty == false)
        #expect(ref == Self.budi)
    }

    @Test("AC-02-2: cancelling returns nil and throws nothing")
    func test_AC0202_cancelReturnsNilAndDoesNotThrow() async {
        let contacts = FakeContactService(pick: .cancelled)
        #expect(await contacts.pick() == nil)
    }

    @Test("AC-02-4 / R-02-2: a rename shows up in a live resolve and nowhere else")
    func test_AC0204_renameDoesNotChangeTheStoredSnapshot() async throws {
        // The product stored this at pick time, in January.
        let stored = Self.budi
        // The operator has since renamed the contact in the Contacts app.
        let contacts = FakeContactService(
            resolve: .found(ContactRef(id: "ABC-123", name: "Budi Grosir"))
        )

        let live = try await contacts.resolve(id: stored.id)

        #expect(live?.name == "Budi Grosir")   // 02 §11: the live lookup moves
        #expect(stored.name == "Budi Santoso") // 02 §11: the snapshot does not
    }

    @Test("R-02-4: a deleted contact resolves to nil, which is not an error")
    func test_R0204_missingContactResolvesToNil() async throws {
        let contacts = FakeContactService(resolve: .gone)
        #expect(try await contacts.resolve(id: "ABC-123") == nil)
    }

    @Test("R-02-4: the DEBUG seed's synthetic supplier identifier is gone, not broken")
    func test_R0204_seedIdentifierResolvesToNil() async throws {
        // Foundations §9: the seed pairs a real name with an identifier that was
        // never in the address book, so this resolve fails permanently — and
        // must degrade to the snapshot rather than raise.
        let contacts = FakeContactService(resolve: .gone)
        #expect(try await contacts.resolve(id: "seed-toko-grosir-budi") == nil)
    }

    @Test("AC-02-5: a refused permission throws contactAccessDenied and nothing else")
    func test_AC0205_deniedResolveThrows() async {
        let contacts = FakeContactService(resolve: .denied)
        await #expect(throws: POSError.contactAccessDenied) {
            _ = try await contacts.resolve(id: "ABC-123")
        }
    }

    @Test("Every error this module raises has an Indonesian message")
    func test_deniedErrorHasAnIndonesianMessage() {
        #expect(POSError.contactAccessDenied.message == "Akses kontak ditolak. Aktifkan di Pengaturan.")
    }
}

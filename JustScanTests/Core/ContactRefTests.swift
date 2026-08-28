//
//  ContactRefTests.swift
//  JustScanTests
//
//  R-02-3's fallback chain and R-02-5's pairing rule, tested where they live.
//  Both are pure functions over strings, which is deliberate: it keeps the
//  branch coverage honest and keeps `import Contacts` out of the test target
//  (AC-02-7).
//

import Foundation
import Testing
@testable import JustScan

struct ContactRefTests {

    // MARK: - R-02-3 · the name fallback chain

    @Test("R-02-3: a formatted full name wins")
    func test_R0203_fullNameWins() {
        let name = ContactRef.snapshotName(
            fullName: "Budi Santoso",
            organizationName: "Toko Grosir Budi"
        )
        #expect(name == "Budi Santoso")
    }

    @Test("R-02-3 / AC-02-6: no person name falls back to the organisation")
    func test_R0203_fallsBackToOrganizationName() {
        // 02 §11, the fourth worked example.
        let name = ContactRef.snapshotName(fullName: nil, organizationName: "Toko Grosir Budi")
        #expect(name == "Toko Grosir Budi")
    }

    @Test("R-02-3: neither name nor organisation falls back to Tanpa Nama")
    func test_R0203_fallsBackToTanpaNama() {
        #expect(ContactRef.snapshotName(fullName: nil, organizationName: nil) == "Tanpa Nama")
    }

    @Test("R-02-3: whitespace counts as empty at every link in the chain")
    func test_R0203_whitespaceOnlyCountsAsEmpty() {
        #expect(ContactRef.snapshotName(fullName: "   ", organizationName: "Toko Grosir Budi")
                == "Toko Grosir Budi")
        #expect(ContactRef.snapshotName(fullName: "", organizationName: "\n\t ") == "Tanpa Nama")
    }

    @Test("R-02-3: a ref's name is never empty once an identifier is set")
    func test_R0203_snapshotIsNeverEmpty() {
        #expect(ContactRef(id: "XYZ-789", name: "").name == "Tanpa Nama")
        #expect(ContactRef(id: "XYZ-789", name: "   ").name == "Tanpa Nama")
    }

    // MARK: - R-02-5 · both fields, or neither

    @Test("R-02-5: both columns present makes a ref")
    func test_R0205_bothColumnsMakeARef() {
        #expect(ContactRef.paired(id: "ABC-123", name: "Budi Santoso")
                == ContactRef(id: "ABC-123", name: "Budi Santoso"))
    }

    @Test("R-02-5: a half-populated row reads as absent, never as half a contact")
    func test_R0205_halfPopulatedReadsAsAbsent() {
        #expect(ContactRef.paired(id: "ABC-123", name: nil) == nil)
        #expect(ContactRef.paired(id: nil, name: "Budi Santoso") == nil)
        #expect(ContactRef.paired(id: "", name: "Budi Santoso") == nil)
        #expect(ContactRef.paired(id: "ABC-123", name: "") == nil)
        #expect(ContactRef.paired(id: nil, name: nil) == nil)
    }

    // MARK: - §11 worked example

    @Test("02 §11: picking Budi Santoso yields exactly the stated ref")
    func test_workedExample_pickedRef() {
        let ref = ContactRef(id: "ABC-123", name: "Budi Santoso")
        #expect(ref.id == "ABC-123")
        #expect(ref.name == "Budi Santoso")
    }
}

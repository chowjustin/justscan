//
//  ContactRef.swift
//  JustScan
//
//  The whole of module 02's data model. Not an entity — a value type that host
//  entities embed as two columns (02 §5, foundations §4).
//
//  Deliberately free of `import Contacts`. That keeps the R-02-3 fallback chain
//  testable without dragging the framework into the test target, which
//  AC-02-7 forbids.
//

import Foundation

struct ContactRef: Equatable, Sendable {
    /// `CNContact.identifier`. **Not stable** — it changes on merge and vanishes
    /// on delete, so a failed resolve is normal, never exceptional (R-02-4).
    let id: String

    /// Display name captured at pick time. Never refreshed (R-02-2), never
    /// empty (R-02-3).
    let name: String

    init(id: String, name: String) {
        self.id = id
        // R-02-3: the snapshot is never empty when an identifier is set. An
        // empty name arriving here can only be a caller's mistake, and
        // "Tanpa Nama" is a readable row where a blank one is a broken one.
        self.name = Self.snapshotName(fullName: name, organizationName: nil)
    }

    /// The last link in the R-02-3 chain.
    static let unnamed = "Tanpa Nama"

    /// R-02-3, expressed over plain strings so every branch is testable without
    /// a `CNContact`. `ContactService` supplies the formatter output and the
    /// organisation name; this decides which one becomes the snapshot.
    static func snapshotName(fullName: String?, organizationName: String?) -> String {
        if let full = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty {
            return full
        }
        if let organization = organizationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !organization.isEmpty {
            return organization
        }
        return unnamed
    }

    /// R-02-5, read direction: two host columns become one value, or nothing.
    /// A row carrying an ID with no name — or a name with no ID — is invalid
    /// state, and this reports it as absent rather than half-present.
    static func paired(id: String?, name: String?) -> ContactRef? {
        guard let id, !id.isEmpty, let name, !name.isEmpty else { return nil }
        return ContactRef(id: id, name: name)
    }
}

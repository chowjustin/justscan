//
//  FakeContactService.swift
//  JustScanTests
//
//  Stands in for the address book. The real picker is out-of-process and the
//  real store needs a device and a granted permission; this proves the contract
//  that 03 and 04 are written against.
//
//  Note what is absent: `import Contacts`. The status crosses the module
//  boundary as `ContactAccess`, so nothing outside `Core/Contacts/` — this file
//  included — has to know the framework exists (AC-02-7).
//

import Foundation
@testable import JustScan

final class FakeContactService: ContactServicing, @unchecked Sendable {
    enum PickOutcome {
        case contact(ContactRef)
        case cancelled
    }

    enum ResolveOutcome {
        /// The contact is still there — possibly renamed since it was picked.
        case found(ContactRef)
        /// Deleted, merged away, or never real (R-02-4).
        case gone
        /// Permission refused, including revoked while backgrounded (02 §8).
        case denied
    }

    var pickOutcome: PickOutcome
    var resolveOutcome: ResolveOutcome
    var authorizationStatus: ContactAccess

    private(set) var pickCount = 0
    private(set) var resolvedIDs: [String] = []
    var resolveCount: Int { resolvedIDs.count }

    init(
        pick: PickOutcome = .cancelled,
        resolve: ResolveOutcome = .gone,
        access: ContactAccess = .granted
    ) {
        self.pickOutcome = pick
        self.resolveOutcome = resolve
        self.authorizationStatus = access
    }

    @MainActor
    func pick() async -> ContactRef? {
        pickCount += 1
        switch pickOutcome {
        case .contact(let ref): return ref
        case .cancelled:        return nil
        }
    }

    func resolve(id: String) async throws -> ContactRef? {
        resolvedIDs.append(id)
        switch resolveOutcome {
        case .found(let ref): return ref
        case .gone:           return nil
        case .denied:         throw POSError.contactAccessDenied
        }
    }
}

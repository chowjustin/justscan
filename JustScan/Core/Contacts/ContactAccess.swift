//
//  ContactAccess.swift
//  JustScan
//
//  Whether a live contact lookup is possible right now, expressed without the
//  Contacts framework.
//
//  02 §7 originally exported `CNAuthorizationStatus` directly. That type cannot
//  cross this folder's boundary: naming it forces `import Contacts` on every
//  caller **and every conformance**, including the test fake, which makes
//  AC-02-7 impossible to satisfy. The whole reason this module exists is to be
//  the only place that knows Contacts exists, so the status crosses the
//  boundary as this instead. Deviation recorded in PROGRESS.md; 02 §7 and §9
//  updated to match.
//

import Foundation

enum ContactAccess: Equatable, Sendable {
    /// Never asked. The picker still works — it prompts for nothing (02 §3).
    case notDetermined
    /// A lookup will be attempted. Covers iOS 18's limited access, where a
    /// contact outside the granted set simply reads as gone (R-02-4).
    case granted
    /// Denied or restricted. The stored snapshot renders and nothing breaks.
    case denied
}

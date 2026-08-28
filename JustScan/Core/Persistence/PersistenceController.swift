//
//  PersistenceController.swift
//  JustScan
//
//  The one place a ModelContainer is constructed (R-01-3). No other type
//  builds one, except tests, which pass `inMemory: true`.
//

import Foundation
import OSLog
import SwiftData

@MainActor
enum PersistenceController {
    private static let log = Logger(subsystem: "chow.JustScan", category: "persistence")

    /// The four model types. CloudKit-shaped from day one (foundations §6):
    /// every property optional or defaulted, every relationship optional with an
    /// explicit inverse, no `@Attribute(.unique)` anywhere.
    static let schema = Schema([
        Product.self,
        StockMovement.self,
        Sale.self,
        SaleLine.self
    ])

    /// R-01-9 — try CloudKit, fall back to local-only, never block trading.
    ///
    /// CloudKit is on from session 1 (D-18) so that every launch validates the
    /// schema. A full iCloud account, a signed-out device, or an unreachable
    /// container degrades to local-only rather than stopping the shop.
    ///
    /// The fallback is logged, never silent. If the *local* store also fails to
    /// load the error propagates: a corrupt store is fatal, and recreating it
    /// would delete the operator's sales (01 §8).
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            // Tests never touch CloudKit.
            return try makeContainer(cloudKitDatabase: .none, inMemory: true)
        }

        do {
            return try makeContainer(cloudKitDatabase: .automatic, inMemory: false)
        } catch {
            log.error("""
                CloudKit container unavailable, falling back to local-only: \
                \(error.localizedDescription, privacy: .public)
                """)
            return try makeContainer(cloudKitDatabase: .none, inMemory: false)
        }
    }

    private static func makeContainer(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        inMemory: Bool
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

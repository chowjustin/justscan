//
//  AppContainer.swift
//  JustScan
//
//  The composition root. The only place a concrete service is constructed
//  (STRUCTURE.md). Views receive it through the environment, which is what
//  makes fakes substitutable in tests without a DI framework.
//
//  It holds exactly what module 01 owns. Modules 02–05 add their own services
//  here as they are built.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let scanner: ScannerServicing
    let contacts: ContactServicing

    /// The single context every repository shares, so one `save()` commits a
    /// whole business operation (see `ProductRepository.save()`).
    private let context: ModelContext

    let products: ProductRepository
    let stockMovements: StockMovementRepository

    init(
        modelContainer: ModelContainer,
        scanner: ScannerServicing,
        contacts: ContactServicing
    ) {
        self.modelContainer = modelContainer
        self.scanner = scanner
        self.contacts = contacts

        let context = ModelContext(modelContainer)
        self.context = context
        self.products = SwiftDataProductRepository(context: context)
        self.stockMovements = SwiftDataStockMovementRepository(context: context)
    }

    #if DEBUG
    /// Foundations §9. Empty-store-only and idempotent, so calling it on every
    /// launch is safe.
    func loadSeedIfNeeded() {
        do {
            try SeedService(products: products, movements: stockMovements).load()
        } catch {
            // DEBUG-only convenience. A failed seed must not stop the app from
            // launching, and it is loud in the console.
            assertionFailure("Seed failed: \(error)")
        }
    }
    #endif
}

// Injected with `.environment(container)` and read with
// `@Environment(AppContainer.self)`. That is the documented pattern for an
// `@Observable` type — no custom `EnvironmentKey` needed.

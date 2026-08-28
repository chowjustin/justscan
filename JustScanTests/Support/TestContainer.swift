//
//  TestContainer.swift
//  JustScanTests
//
//  In-memory container. Tests never touch disk and never touch CloudKit
//  (R-01-3).
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
enum TestContainer {
    /// A fresh, isolated store per call.
    static func make() throws -> ModelContainer {
        try PersistenceController.container(inMemory: true)
    }

    /// A container plus repositories wired to one shared context, matching how
    /// `AppContainer` wires them in the app.
    static func repositories() throws -> (
        container: ModelContainer,
        context: ModelContext,
        products: ProductRepository,
        movements: StockMovementRepository
    ) {
        let container = try make()
        let context = ModelContext(container)
        return (
            container,
            context,
            SwiftDataProductRepository(context: context),
            SwiftDataStockMovementRepository(context: context)
        )
    }

    /// Module 04's wiring: the two module 03 services plus `SaleService`, all
    /// over the one shared context, exactly as `AppContainer` builds them.
    ///
    /// `productRepository` is handed back so a test can force `save()` to fail
    /// on the real store (AC-04-16), and `container` so a **second** context
    /// can be asked what actually landed.
    typealias SaleWiring = (
        container: ModelContainer,
        context: ModelContext,
        products: FailingSaveProductRepository,
        movements: StockMovementRepository,
        catalogue: CatalogueServicing,
        stock: StockServicing,
        sales: SaleServicing
    )

    static func sale(saveError: Error? = nil) throws -> SaleWiring {
        let container = try make()
        let context = ModelContext(container)
        let products = FailingSaveProductRepository(
            wrapping: SwiftDataProductRepository(context: context),
            saveError: saveError
        )
        let movements = SwiftDataStockMovementRepository(context: context)
        let stock = StockService(products: products, movements: movements)
        return (
            container,
            context,
            products,
            movements,
            CatalogueService(products: products),
            stock,
            SaleService(sales: SwiftDataSaleRepository(context: context),
                        products: products,
                        stock: stock)
        )
    }

    /// The two module 03 services over one shared context, wired exactly as
    /// `AppContainer` wires them — so a test exercises the real save path
    /// rather than an arrangement that only exists in tests.
    static func catalogue() throws -> (
        container: ModelContainer,
        context: ModelContext,
        products: ProductRepository,
        movements: StockMovementRepository,
        catalogue: CatalogueServicing,
        stock: StockServicing
    ) {
        let wiring = try repositories()
        return (
            wiring.container,
            wiring.context,
            wiring.products,
            wiring.movements,
            CatalogueService(products: wiring.products),
            StockService(products: wiring.products, movements: wiring.movements)
        )
    }
}

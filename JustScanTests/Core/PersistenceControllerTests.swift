//
//  PersistenceControllerTests.swift
//  JustScanTests
//
//  AC-01-6 — an in-memory container that never touches disk.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct PersistenceControllerTests {
    @Test("AC-01-6: build an in-memory container and insert a Product without touching disk")
    func test_AC0106_insertsAProductInMemory() throws {
        let container = try TestContainer.make()
        let context = ModelContext(container)

        context.insert(Product(name: "Chitato Sapi Panggang 68g", priceRp: 12_000))
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Product>())
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Chitato Sapi Panggang 68g")
        #expect(stored.first?.priceRp == 12_000)
    }

    @Test("AC-01-6: the in-memory configuration really is in memory")
    func test_AC0106_configurationIsInMemoryOnly() throws {
        let container = try TestContainer.make()
        // Computed outside the macro: `allSatisfy` is `rethrows`, and #expect
        // decomposes it into a context that cannot prove it does not throw.
        let allInMemory = container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        #expect(allInMemory)
    }

    @Test("Each container is isolated — one test never sees another's rows")
    func test_AC0106_containersAreIsolated() throws {
        let first = ModelContext(try TestContainer.make())
        first.insert(Product(name: "Aqua 600ml", priceRp: 4_000))
        try first.save()

        let second = ModelContext(try TestContainer.make())
        #expect(try second.fetch(FetchDescriptor<Product>()).isEmpty)
    }

    @Test("The schema holds exactly the four entities in the foundations §4 map")
    func test_R0103_schemaHoldsTheFourEntities() throws {
        let names = Set(PersistenceController.schema.entities.map(\.name))
        #expect(names == ["Product", "StockMovement", "Sale", "SaleLine"])
    }

    @Test("All four models round-trip, relationships and enum accessors included")
    func test_R0103_allFourModelsRoundTrip() throws {
        let context = ModelContext(try TestContainer.make())

        let product = Product(name: "Teh Botol Sosro 350ml", priceRp: 5_000, barcode: "8992772000108")
        context.insert(product)
        context.insert(StockMovement(product: product, delta: 12, reason: .opening))

        let sale = Sale(number: "20260821-001", totalRp: 5_000, method: .qris)
        context.insert(sale)
        let line = SaleLine(
            sale: sale,
            productID: product.id,
            nameSnapshot: "Teh Botol Sosro 350ml",
            unitPriceRp: 5_000,
            qty: 1,
            lineTotalRp: 5_000
        )
        context.insert(line)
        try context.save()

        let storedProduct = try #require(try context.fetch(FetchDescriptor<Product>()).first)
        #expect(storedProduct.movements?.count == 1)
        #expect(storedProduct.movements?.first?.reason == .opening)

        let storedSale = try #require(try context.fetch(FetchDescriptor<Sale>()).first)
        #expect(storedSale.lines?.count == 1)
        #expect(storedSale.method == .qris)
        #expect(storedSale.status == .completed)
        // QRIS carries nil, never 0 (R-04-10).
        #expect(storedSale.cashReceivedRp == nil)
        #expect(storedSale.changeRp == nil)
        // The line references the product by weak UUID, not by relationship (D-15).
        #expect(storedSale.lines?.first?.productID == storedProduct.id)
    }

    @Test("An unknown enum raw value falls back rather than crashing")
    func test_R0103_enumAccessorsFallBackOnUnknownRawValues() throws {
        let context = ModelContext(try TestContainer.make())

        let movement = StockMovement(delta: 1, reason: .restock)
        movement.reasonRaw = "teleported"          // a value a future schema wrote
        let sale = Sale(number: "20260821-002")
        sale.paymentMethodRaw = "crypto"
        sale.statusRaw = "refunded"
        context.insert(movement)
        context.insert(sale)
        try context.save()

        #expect(movement.reason == .adjustment)
        #expect(sale.method == .cash)
        #expect(sale.status == .completed)
    }
}

//
//  SeedServiceTests.swift
//  JustScanTests
//
//  AC-01-8 — exactly 5 products and 4 opening movements, and idempotent.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct SeedServiceTests {
    private func movementCount(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<StockMovement>()).count
    }

    @Test("AC-01-8: an empty store seeds exactly 5 products and 4 opening movements")
    func test_AC0108_seedsFiveProductsAndFourMovements() throws {
        let wiring = try TestContainer.repositories()
        try SeedService(products: wiring.products, movements: wiring.movements).load()

        #expect(try wiring.products.all().count == 5)
        #expect(try movementCount(wiring.context) == 4)
    }

    @Test("AC-01-8: running the seed twice still produces 5 and 4")
    func test_AC0108_isIdempotent() throws {
        let wiring = try TestContainer.repositories()
        let seed = SeedService(products: wiring.products, movements: wiring.movements)

        try seed.load()
        try seed.load()

        #expect(try wiring.products.all().count == 5)
        #expect(try movementCount(wiring.context) == 4)
    }

    @Test("Foundations §9: the seeded catalogue matches the spec table exactly")
    func test_seedMatchesTheFoundationsTable() throws {
        let wiring = try TestContainer.repositories()
        try SeedService(products: wiring.products, movements: wiring.movements).load()

        let byName = Dictionary(
            uniqueKeysWithValues: try wiring.products.all().map { ($0.name, $0) }
        )

        let expected: [(String, String?, Int, Int)] = [
            ("Chitato Sapi Panggang 68g", "8992775311011", 12_000, 24),
            ("Teh Botol Sosro 350ml",     "8992772000108",  5_000, 12),
            ("Indomie Goreng 85g",        "8998866200608",  3_500, 40),
            ("Aqua 600ml",                "8886008101053",  4_000, 24),
            ("Gorengan (per pcs)",        nil,              2_000,  0)
        ]

        for (name, barcode, priceRp, stockQty) in expected {
            let product = try #require(byName[name], "\(name)")
            #expect(product.barcode == barcode, "\(name)")
            #expect(product.priceRp == priceRp, "\(name)")
            #expect(product.stockQty == stockQty, "\(name)")
        }
    }

    @Test("R-03-9/R-03-13: zero stock is the absence of movements, never a movement of zero")
    func test_R0313_gorenganHasNoMovements() throws {
        let wiring = try TestContainer.repositories()
        try SeedService(products: wiring.products, movements: wiring.movements).load()

        let gorengan = try #require(
            try wiring.products.all().first { $0.name == "Gorengan (per pcs)" }
        )
        #expect(gorengan.stockQty == 0)
        #expect(try wiring.movements.movements(for: gorengan).isEmpty)

        // And no movement anywhere carries a zero delta.
        let all = try wiring.context.fetch(FetchDescriptor<StockMovement>())
        let noZeroDeltas = all.allSatisfy { $0.delta != 0 }
        #expect(noZeroDeltas)
    }

    @Test("Every seeded movement is an opening movement matching its product's stock")
    func test_seedMovementsAreOpeningAndMatchStock() throws {
        let wiring = try TestContainer.repositories()
        try SeedService(products: wiring.products, movements: wiring.movements).load()

        for product in try wiring.products.all() where product.stockQty > 0 {
            let movements = try wiring.movements.movements(for: product)
            #expect(movements.count == 1, "\(product.name)")
            let opening = try #require(movements.first, "\(product.name)")
            #expect(opening.reason == .opening, "\(product.name)")
            #expect(opening.delta == product.stockQty, "\(product.name)")
            // R-03-13: only .sale and .void carry a saleID.
            #expect(opening.saleID == nil, "\(product.name)")
        }
    }

    @Test("D-11: seeded suppliers carry both columns, and only where §9 says so")
    func test_D11_seedSuppliersArePaired() throws {
        let wiring = try TestContainer.repositories()
        try SeedService(products: wiring.products, movements: wiring.movements).load()

        let products = try wiring.products.all()
        let withSupplier = products.filter { $0.supplierName != nil }
        #expect(withSupplier.count == 3)

        for product in withSupplier {
            #expect(product.supplierName == "Toko Grosir Budi", "\(product.name)")
            #expect(product.supplierContactID == "seed-toko-grosir-budi", "\(product.name)")
        }
        // Aqua and Gorengan have no supplier — both columns nil, never one of them.
        for product in products where product.supplierName == nil {
            #expect(product.supplierContactID == nil, "\(product.name)")
        }
    }

    @Test("A non-empty store is left exactly as it is")
    func test_seedSkipsANonEmptyStore() throws {
        let wiring = try TestContainer.repositories()
        wiring.products.insert(Product(name: "Kopi Hitam", priceRp: 3_000))
        try wiring.products.save()

        try SeedService(products: wiring.products, movements: wiring.movements).load()

        let products = try wiring.products.all()
        #expect(products.count == 1)
        #expect(products.first?.name == "Kopi Hitam")
        #expect(try movementCount(wiring.context) == 0)
    }
}

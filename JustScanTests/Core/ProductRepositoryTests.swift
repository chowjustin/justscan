//
//  ProductRepositoryTests.swift
//  JustScanTests
//
//  R-01-4 — services depend on the protocol, so these test the SwiftData
//  conformance behind it. The *rules* that call these methods belong to module
//  03; what is pinned here is only fetch/insert/save behaviour.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct ProductRepositoryTests {
    @Test("R-01-4: the concrete repository is reachable only through the protocol")
    func test_R0104_isUsedThroughItsProtocol() throws {
        let wiring = try TestContainer.repositories()
        let repository: ProductRepository = wiring.products
        #expect(try repository.all().isEmpty)
    }

    @Test("Nothing is persisted until save()")
    func test_insertIsNotCommittedUntilSave() throws {
        let wiring = try TestContainer.repositories()
        wiring.products.insert(Product(name: "Aqua 600ml", priceRp: 4_000))

        // A separate context onto the same store sees nothing yet.
        let observer = ModelContext(wiring.container)
        #expect(try observer.fetch(FetchDescriptor<Product>()).isEmpty)

        try wiring.products.save()
        #expect(try ModelContext(wiring.container).fetch(FetchDescriptor<Product>()).count == 1)
    }

    @Test("One save() commits products and movements together (R-03-11)")
    func test_R0311_oneSaveCommitsBothRepositories() throws {
        let wiring = try TestContainer.repositories()
        let product = Product(name: "Indomie Goreng 85g", priceRp: 3_500, stockQty: 40)
        wiring.products.insert(product)
        wiring.movements.insert(StockMovement(product: product, delta: 40, reason: .opening))

        try wiring.products.save()

        let observer = ModelContext(wiring.container)
        #expect(try observer.fetch(FetchDescriptor<Product>()).count == 1)
        #expect(try observer.fetch(FetchDescriptor<StockMovement>()).count == 1)
    }

    @Test("findBy(barcode:) locates a live product")
    func test_findByBarcodeFindsALiveProduct() throws {
        let wiring = try TestContainer.repositories()
        wiring.products.insert(
            Product(name: "Chitato Sapi Panggang 68g", priceRp: 12_000, barcode: "8992775311011")
        )
        try wiring.products.save()

        let found = try wiring.products.findBy(barcode: "8992775311011")
        #expect(found?.name == "Chitato Sapi Panggang 68g")
        #expect(try wiring.products.findBy(barcode: "0000000000000") == nil)
    }

    @Test("R-03-1/R-03-12: a soft-deleted product is invisible to lookup and to all()")
    func test_R0312_softDeletedProductsAreInvisible() throws {
        let wiring = try TestContainer.repositories()
        let product = Product(name: "Kopi Hitam", priceRp: 3_000, barcode: "8991234567890")
        wiring.products.insert(product)
        try wiring.products.save()

        product.deletedAt = Date()
        try wiring.products.save()

        #expect(try wiring.products.findBy(barcode: "8991234567890") == nil)
        #expect(try wiring.products.all().isEmpty)

        // The row itself survives — soft delete never removes it (R-03-10 audit trail).
        #expect(try wiring.context.fetch(FetchDescriptor<Product>()).count == 1)
    }

    @Test("R-03-3: a nil barcode is not a value and never collides")
    func test_R0303_nilBarcodesDoNotCollide() throws {
        let wiring = try TestContainer.repositories()
        wiring.products.insert(Product(name: "Gorengan (per pcs)", priceRp: 2_000))
        wiring.products.insert(Product(name: "Es Teh", priceRp: 3_000))
        try wiring.products.save()

        #expect(try wiring.products.all().count == 2)
    }

    @Test("all() is name-ascending")
    func test_allIsNameSorted() throws {
        let wiring = try TestContainer.repositories()
        for name in ["Teh Botol Sosro 350ml", "Aqua 600ml", "Indomie Goreng 85g"] {
            wiring.products.insert(Product(name: name, priceRp: 1_000))
        }
        try wiring.products.save()

        #expect(try wiring.products.all().map(\.name) == [
            "Aqua 600ml", "Indomie Goreng 85g", "Teh Botol Sosro 350ml"
        ])
    }

    @Test("movements(for:) is newest-first and scoped to one product")
    func test_movementsAreNewestFirstAndScoped() throws {
        let wiring = try TestContainer.repositories()
        let chitato = Product(name: "Chitato Sapi Panggang 68g", priceRp: 12_000)
        let aqua = Product(name: "Aqua 600ml", priceRp: 4_000)
        wiring.products.insert(chitato)
        wiring.products.insert(aqua)

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        wiring.movements.insert(StockMovement(product: chitato, delta: 24, reason: .opening, createdAt: base))
        wiring.movements.insert(StockMovement(product: chitato, delta: -2, reason: .sale, saleID: UUID(), createdAt: base.addingTimeInterval(60)))
        wiring.movements.insert(StockMovement(product: aqua, delta: 24, reason: .opening, createdAt: base))
        try wiring.products.save()

        let history = try wiring.movements.movements(for: chitato)
        #expect(history.count == 2)
        #expect(history.map(\.delta) == [-2, 24])
        #expect(try wiring.movements.movements(for: aqua).count == 1)
    }
}

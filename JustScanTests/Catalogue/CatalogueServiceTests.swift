//
//  CatalogueServiceTests.swift
//  JustScanTests
//
//  R-03-1..5, R-03-12, R-03-14, and the §11 barcode-collision example.
//  Against a real in-memory container (03 §13.9), so the uniqueness check runs
//  through the same repository the app uses.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct CatalogueServiceTests {

    // MARK: - R-03-2, R-03-1 — uniqueness

    @Test("R-03-2/AC-03-3: a duplicate barcode throws, carrying the existing product's ID")
    func test_R0302_duplicateBarcodeThrowsWithExistingID() throws {
        let wiring = try TestContainer.catalogue()
        let first = try wiring.catalogue.create(
            name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
            barcode: "8992775311011", supplier: nil
        )

        #expect(throws: POSError.barcodeAlreadyExists(productID: first.id)) {
            _ = try wiring.catalogue.create(
                name: "Chitato Rasa Keju 68g", priceRp: 12_000,
                barcode: "8992775311011", supplier: nil
            )
        }

        // Nothing was inserted by the failed call.
        #expect(try wiring.catalogue.all().count == 1)
    }

    @Test("R-03-1: uniqueness is scoped to non-deleted rows (03 §8)")
    func test_R0301_uniquenessIsScopedToLiveRows() throws {
        let wiring = try TestContainer.catalogue()
        let first = try wiring.catalogue.create(
            name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
            barcode: "8992775311011", supplier: nil
        )
        try wiring.catalogue.softDelete(first)

        // The code is free again, and the old row keeps it on a dead product.
        let second = try wiring.catalogue.create(
            name: "Chitato Sapi Panggang 68g", priceRp: 13_000,
            barcode: "8992775311011", supplier: nil
        )
        #expect(second.id != first.id)
        #expect(try wiring.context.fetch(FetchDescriptor<Product>()).count == 2)
    }

    @Test("R-03-3/AC-03-4: two nil barcodes do not collide")
    func test_R0303_nilBarcodesDoNotCollide() throws {
        let wiring = try TestContainer.catalogue()
        _ = try wiring.catalogue.create(name: "Gorengan (per pcs)", priceRp: 2_000,
                                        barcode: nil, supplier: nil)
        _ = try wiring.catalogue.create(name: "Es Teh", priceRp: 3_000,
                                        barcode: nil, supplier: nil)

        #expect(try wiring.catalogue.all().map(\.name) == ["Es Teh", "Gorengan (per pcs)"])
    }

    @Test("R-03-3: an empty barcode string is absence, not a value")
    func test_R0303_emptyBarcodeIsTreatedAsAbsent() throws {
        let wiring = try TestContainer.catalogue()
        let first = try wiring.catalogue.create(name: "Gorengan (per pcs)", priceRp: 2_000,
                                                barcode: "  ", supplier: nil)
        #expect(first.barcode == nil)

        // A second blank does not collide with the first.
        _ = try wiring.catalogue.create(name: "Es Teh", priceRp: 3_000,
                                        barcode: "", supplier: nil)
        #expect(try wiring.catalogue.all().count == 2)
    }

    // MARK: - R-03-4, R-03-5 — validation

    @Test("R-03-4/AC-03-5: an empty or whitespace-only name is rejected")
    func test_R0304_blankNameIsRejected() throws {
        let wiring = try TestContainer.catalogue()
        for blank in ["", "   ", "\n\t"] {
            #expect(throws: POSError.validationFailed(field: "name")) {
                _ = try wiring.catalogue.create(name: blank, priceRp: 12_000,
                                                barcode: nil, supplier: nil)
            }
        }
        #expect(try wiring.catalogue.all().isEmpty)
    }

    @Test("R-03-4: a name is trimmed, and 81 characters is too long")
    func test_R0304_nameIsTrimmedAndBounded() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "  Aqua 600ml  ", priceRp: 4_000,
                                                  barcode: nil, supplier: nil)
        #expect(product.name == "Aqua 600ml")

        #expect(throws: POSError.validationFailed(field: "name")) {
            _ = try wiring.catalogue.create(name: String(repeating: "a", count: 81),
                                            priceRp: 4_000, barcode: nil, supplier: nil)
        }
        // 80 is the boundary and is accepted.
        let atLimit = try wiring.catalogue.create(name: String(repeating: "a", count: 80),
                                                  priceRp: 4_000, barcode: nil, supplier: nil)
        #expect(atLimit.name.count == 80)
    }

    @Test("R-03-4: names are not unique")
    func test_R0304_namesAreNotUnique() throws {
        let wiring = try TestContainer.catalogue()
        _ = try wiring.catalogue.create(name: "Kopi Hitam", priceRp: 3_000,
                                        barcode: nil, supplier: nil)
        _ = try wiring.catalogue.create(name: "Kopi Hitam", priceRp: 4_000,
                                        barcode: nil, supplier: nil)
        #expect(try wiring.catalogue.all().count == 2)
    }

    @Test("R-03-5/AC-03-6: a price of zero or less is rejected")
    func test_R0305_nonPositivePriceIsRejected() throws {
        let wiring = try TestContainer.catalogue()
        for price in [0, -1, -12_000] {
            #expect(throws: POSError.validationFailed(field: "price")) {
                _ = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: price,
                                                barcode: nil, supplier: nil)
            }
        }
    }

    @Test("R-03-4/R-03-5: update validates exactly as create does")
    func test_R0304_R0305_updateValidatesToo() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: 4_000,
                                                  barcode: nil, supplier: nil)

        #expect(throws: POSError.validationFailed(field: "name")) {
            try wiring.catalogue.update(product, name: " ", priceRp: 4_000, supplier: nil)
        }
        #expect(throws: POSError.validationFailed(field: "price")) {
            try wiring.catalogue.update(product, name: "Aqua 600ml", priceRp: 0, supplier: nil)
        }
        // Neither failed call wrote anything.
        #expect(product.name == "Aqua 600ml")
        #expect(product.priceRp == 4_000)
    }

    // MARK: - Creation shape

    @Test("03 §3.9: a new product starts at zero with no movement written")
    func test_newProductHasNoOpeningMovement() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000,
                                                  barcode: "8992775311011", supplier: nil)

        #expect(product.stockQty == 0)
        #expect(try wiring.stock.movements(for: product).isEmpty)
        #expect(try wiring.context.fetch(FetchDescriptor<StockMovement>()).isEmpty)
    }

    @Test("R-02-5: a supplier lands on both columns, or on neither")
    func test_R0205_supplierIsStoredAsAPair() throws {
        let wiring = try TestContainer.catalogue()
        let budi = ContactRef(id: "ABC-123", name: "Toko Grosir Budi")

        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000, barcode: nil, supplier: budi)
        #expect(product.supplierContactID == "ABC-123")
        #expect(product.supplierName == "Toko Grosir Budi")

        try wiring.catalogue.update(product, name: product.name,
                                    priceRp: product.priceRp, supplier: nil)
        #expect(product.supplierContactID == nil)
        #expect(product.supplierName == nil)
    }

    @Test("update touches updatedAt; create sets both stamps")
    func test_updatedAtIsTouchedOnEdit() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: 4_000,
                                                  barcode: nil, supplier: nil)
        let created = product.updatedAt
        #expect(product.createdAt == created)

        try wiring.catalogue.update(product, name: "Aqua 600ml", priceRp: 4_500, supplier: nil)
        #expect(product.updatedAt > created)
        #expect(product.priceRp == 4_500)
    }

    // MARK: - R-03-12 — soft delete

    @Test("R-03-12/AC-03-12: a deleted product is absent from all(), search(), and findBy()")
    func test_R0312_softDeletedProductIsInvisible() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000,
                                                  barcode: "8992775311011", supplier: nil)

        try wiring.catalogue.softDelete(product)

        #expect(product.deletedAt != nil)
        #expect(try wiring.catalogue.all().isEmpty)
        #expect(try wiring.catalogue.search("Chitato").isEmpty)
        #expect(try wiring.catalogue.findBy(barcode: "8992775311011") == nil)

        // The row itself survives — soft delete never removes it.
        #expect(try wiring.context.fetch(FetchDescriptor<Product>()).count == 1)
    }

    @Test("03 §8: deleting a product with stock keeps its movements for audit")
    func test_deletedProductKeepsItsMovements() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000, barcode: nil, supplier: nil)
        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)
        try wiring.catalogue.softDelete(product)

        #expect(try wiring.stock.movements(for: product).count == 1)
    }

    // MARK: - R-03-14

    @Test("R-03-14: update and softDelete refuse a soft-deleted product")
    func test_R0314_writesRefuseADeletedProduct() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: 4_000,
                                                  barcode: nil, supplier: nil)
        try wiring.catalogue.softDelete(product)

        #expect(throws: POSError.productNotFound) {
            try wiring.catalogue.update(product, name: "Aqua 1L", priceRp: 6_000, supplier: nil)
        }
        #expect(throws: POSError.productNotFound) {
            try wiring.catalogue.softDelete(product)
        }
        #expect(product.name == "Aqua 600ml")
    }

    @Test("R-03-14: a product that was never inserted is missing, not editable")
    func test_R0314_writesRefuseAnUninsertedProduct() throws {
        let wiring = try TestContainer.catalogue()
        let stranger = Fixtures.gorengan()

        #expect(throws: POSError.productNotFound) {
            try wiring.catalogue.update(stranger, name: "Gorengan", priceRp: 2_500, supplier: nil)
        }
        #expect(throws: POSError.productNotFound) {
            try wiring.catalogue.softDelete(stranger)
        }
    }

    // MARK: - Reads

    @Test("all() excludes deleted rows and is name-ascending")
    func test_allIsNameSortedAndExcludesDeleted() throws {
        let wiring = try TestContainer.catalogue()
        for name in ["Teh Botol Sosro 350ml", "Aqua 600ml", "Indomie Goreng 85g"] {
            _ = try wiring.catalogue.create(name: name, priceRp: 1_000,
                                            barcode: nil, supplier: nil)
        }

        #expect(try wiring.catalogue.all().map(\.name) == [
            "Aqua 600ml", "Indomie Goreng 85g", "Teh Botol Sosro 350ml"
        ])
    }

    @Test("search() matches a name fragment case-insensitively; a blank query is no filter")
    func test_searchMatchesNameFragmentCaseInsensitively() throws {
        let wiring = try TestContainer.catalogue()
        _ = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                                        barcode: nil, supplier: nil)
        _ = try wiring.catalogue.create(name: "Teh Botol Sosro 350ml", priceRp: 5_000,
                                        barcode: nil, supplier: nil)

        #expect(try wiring.catalogue.search("chitato").map(\.name) == ["Chitato Sapi Panggang 68g"])
        #expect(try wiring.catalogue.search("SOSRO").map(\.name) == ["Teh Botol Sosro 350ml"])
        #expect(try wiring.catalogue.search("botol").count == 1)
        #expect(try wiring.catalogue.search("   ").count == 2)
        #expect(try wiring.catalogue.search("kopi").isEmpty)
    }

    @Test("findBy(barcode:) trims what a scanner hands it")
    func test_findByBarcodeTrimsInput() throws {
        let wiring = try TestContainer.catalogue()
        _ = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                                        barcode: "8992775311011", supplier: nil)

        #expect(try wiring.catalogue.findBy(barcode: "8992775311011\n") != nil)
        #expect(try wiring.catalogue.findBy(barcode: " ") == nil)
    }

    // MARK: - AC-03-13 — the snapshot consequence

    @Test("AC-03-13: editing a price leaves every existing SaleLine.unitPriceRp alone")
    func test_AC0313_priceEditDoesNotTouchPastSaleLines() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000, barcode: nil, supplier: nil)

        // A completed line, snapshotted at the price of the day (D-15, R-04-3).
        // Sale and SaleLine are module 04's entities; they are storage-only
        // here, and this is the one criterion that cannot be shown without them.
        let sale = Sale(number: "20260821-001", totalRp: 24_000)
        let line = SaleLine(sale: sale, productID: product.id,
                            nameSnapshot: product.name, unitPriceRp: 12_000,
                            qty: 2, lineTotalRp: 24_000)
        wiring.context.insert(sale)
        wiring.context.insert(line)
        try wiring.products.save()

        try wiring.catalogue.update(product, name: product.name,
                                    priceRp: 15_000, supplier: nil)

        #expect(product.priceRp == 15_000)
        #expect(line.unitPriceRp == 12_000)
        #expect(line.lineTotalRp == 24_000)
        #expect(line.nameSnapshot == "Chitato Sapi Panggang 68g")
    }

    // MARK: - Persistence failures

    @Test("A repository throw is wrapped in persistenceFailed, never swallowed")
    func test_saveFailureSurfacesAsPersistenceFailed() throws {
        let repository = InMemoryProductRepository()
        repository.saveError = CocoaError(.fileWriteUnknown)
        let service = CatalogueService(products: repository)

        var thrown: POSError?
        do {
            _ = try service.create(name: "Aqua 600ml", priceRp: 4_000,
                                   barcode: nil, supplier: nil)
        } catch let error as POSError {
            thrown = error
        }

        guard case .persistenceFailed = thrown else {
            Issue.record("expected persistenceFailed, got \(String(describing: thrown))")
            return
        }
    }
}

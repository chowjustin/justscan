//
//  StockServiceTests.swift
//  JustScanTests
//
//  R-03-6..11, R-03-13, R-03-14 — the ledger arithmetic and the atomic cache
//  update. The §11 worked example is reproduced exactly; approximately right
//  is wrong here.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct StockServiceTests {

    /// A saved, live product to move stock against.
    private func makeProduct(
        _ wiring: (container: ModelContainer, context: ModelContext,
                   products: ProductRepository, movements: StockMovementRepository,
                   catalogue: CatalogueServicing, stock: StockServicing),
        name: String = "Chitato Sapi Panggang 68g",
        priceRp: Int = 12_000
    ) throws -> Product {
        try wiring.catalogue.create(name: name, priceRp: priceRp,
                                    barcode: nil, supplier: nil)
    }

    // MARK: - R-03-11 — one movement, one cache update, one save

    @Test("R-03-11/AC-03-8: adding 24 writes exactly one +24 restock and caches 24")
    func test_R0311_AC0308_addStockWritesOneMovementAndUpdatesCache() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        #expect(product.stockQty == 0)

        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)

        let ledger = try wiring.stock.movements(for: product)
        #expect(ledger.count == 1)
        #expect(ledger[0].delta == 24)
        #expect(ledger[0].reason == .restock)
        #expect(ledger[0].saleID == nil)
        #expect(product.stockQty == 24)

        // Both landed in the same commit — a separate context onto the same
        // store sees the movement and the cache together.
        let observer = ModelContext(wiring.container)
        #expect(try observer.fetch(FetchDescriptor<StockMovement>()).count == 1)
        #expect(try observer.fetch(FetchDescriptor<Product>()).first?.stockQty == 24)
    }

    @Test("R-03-11: a failed save leaves nothing half-written")
    func test_R0311_saveFailureIsSurfacedNotSwallowed() throws {
        let products = InMemoryProductRepository()
        let ledger = InMemoryStockMovementRepository()
        let product = Fixtures.chitato()
        products.insert(product)
        products.saveError = CocoaError(.fileWriteUnknown)
        let stock = StockService(products: products, movements: ledger)

        var thrown: POSError?
        do {
            try stock.record(product: product, delta: 24, reason: .restock,
                             note: nil, saleID: nil)
        } catch let error as POSError {
            thrown = error
        }

        guard case .persistenceFailed = thrown else {
            Issue.record("expected persistenceFailed, got \(String(describing: thrown))")
            return
        }
        // Exactly one save was attempted for the operation (R-03-11).
        #expect(products.saveCount == 1)
    }

    // MARK: - R-03-13 — reason and saleID pairing

    @Test("R-03-13: a sale or void movement must carry a saleID")
    func test_R0313_saleAndVoidRequireASaleID() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)

        for reason in [StockReason.sale, .void] {
            #expect(throws: POSError.validationFailed(field: "reason")) {
                try wiring.stock.record(product: product, delta: -1, reason: reason,
                                        note: nil, saleID: nil)
            }
        }
        #expect(try wiring.stock.movements(for: product).isEmpty)
        #expect(product.stockQty == 0)
    }

    @Test("R-03-13: opening, restock, and adjustment must not carry one")
    func test_R0313_otherReasonsRejectASaleID() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)

        for reason in [StockReason.opening, .restock, .adjustment] {
            #expect(throws: POSError.validationFailed(field: "reason")) {
                try wiring.stock.record(product: product, delta: 1, reason: reason,
                                        note: nil, saleID: UUID())
            }
        }
        #expect(try wiring.stock.movements(for: product).isEmpty)
    }

    @Test("R-03-13/R-03-9: a sale movement with its saleID is accepted and traceable")
    func test_R0313_saleMovementCarriesItsSaleID() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        let saleID = UUID()

        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)
        try wiring.stock.record(product: product, delta: -2, reason: .sale,
                                note: nil, saleID: saleID)

        let newest = try #require(try wiring.stock.movements(for: product).first)
        #expect(newest.reason == .sale)
        #expect(newest.saleID == saleID)
        #expect(product.stockQty == 22)
    }

    @Test("R-03-13: a movement of zero is never written")
    func test_R0313_zeroDeltaIsRejected() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)

        #expect(throws: POSError.validationFailed(field: "qty")) {
            try wiring.stock.record(product: product, delta: 0, reason: .restock,
                                    note: nil, saleID: nil)
        }
        #expect(try wiring.stock.movements(for: product).isEmpty)
    }

    // MARK: - R-03-7 — negative stock

    @Test("R-03-7/AC-03-11: stock goes negative and is never clamped")
    func test_R0307_AC0311_stockIsNotClamped() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)

        try wiring.stock.record(product: product, delta: 2, reason: .restock,
                                note: nil, saleID: nil)
        try wiring.stock.record(product: product, delta: -5, reason: .sale,
                                note: nil, saleID: UUID())

        #expect(product.stockQty == -3)
        #expect(try wiring.stock.recompute(product: product) == -3)
    }

    // MARK: - adjust

    @Test("§11/AC-03-9: counting the current quantity writes nothing at all")
    func test_AC0309_noOpAdjustmentWritesNothing() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        try wiring.stock.record(product: product, delta: 21, reason: .restock,
                                note: nil, saleID: nil)

        try wiring.stock.adjust(product: product, countedQty: 21, note: "Salah hitung")

        #expect(try wiring.stock.movements(for: product).count == 1)
        #expect(product.stockQty == 21)
    }

    @Test("§11: counting 21 against a cached 24 writes a −3 adjustment")
    func test_adjustComputesTheDeltaFromTheCount() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)

        try wiring.stock.adjust(product: product, countedQty: 21, note: "Kedaluwarsa")

        let newest = try #require(try wiring.stock.movements(for: product).first)
        #expect(newest.delta == -3)
        #expect(newest.reason == .adjustment)
        #expect(newest.note == "Kedaluwarsa")
        #expect(newest.saleID == nil)
        #expect(product.stockQty == 21)
    }

    @Test("adjust rejects a negative count and a blank reason")
    func test_adjustValidatesItsInputs() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)

        #expect(throws: POSError.validationFailed(field: "qty")) {
            try wiring.stock.adjust(product: product, countedQty: -1, note: "Hilang")
        }
        #expect(throws: POSError.validationFailed(field: "reason")) {
            try wiring.stock.adjust(product: product, countedQty: 5, note: "  ")
        }
        #expect(try wiring.stock.movements(for: product).isEmpty)
    }

    // MARK: - recompute and the §11 worked example

    @Test("AC-03-10/§11: the worked ledger caches 21 and recomputes to 21")
    func test_AC0310_workedExampleIsExact() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        let saleID = UUID()

        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)
        try wiring.stock.record(product: product, delta: -2, reason: .sale,
                                note: nil, saleID: saleID)
        try wiring.stock.record(product: product, delta: 2, reason: .void,
                                note: nil, saleID: saleID)
        try wiring.stock.adjust(product: product, countedQty: 21, note: "Kedaluwarsa")

        // 24 − 2 + 2 − 3 = 21
        #expect(product.stockQty == 21)
        #expect(try wiring.stock.recompute(product: product) == 21)
        #expect(product.stockQty == 21)

        let ledger = try wiring.stock.movements(for: product)
        #expect(ledger.count == 4)
        #expect(ledger.map(\.delta) == [-3, 2, -2, 24])   // newest first
        #expect(ledger.map(\.reason) == [.adjustment, .void, .sale, .restock])
    }

    @Test("R-03-6: recompute overwrites a cache that drifted, and reports the truth")
    func test_R0306_recomputeRebuildsTheCacheFromTheLedger() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)

        // Simulate a drifted cache — the exact bug recompute exists to surface.
        product.stockQty = 99

        #expect(try wiring.stock.recompute(product: product) == 24)
        #expect(product.stockQty == 24)
    }

    @Test("R-03-13: a product with no movements recomputes to zero, not to a movement of zero")
    func test_R0313_zeroStockIsTheAbsenceOfMovements() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring, name: "Gorengan (per pcs)", priceRp: 2_000)

        #expect(try wiring.stock.recompute(product: product) == 0)
        #expect(try wiring.stock.movements(for: product).isEmpty)
    }

    // MARK: - R-03-10 — immutability

    @Test("R-03-10: a wrong movement is corrected by an offset, never removed")
    func test_R0310_correctionIsAnOffsettingMovement() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)

        try wiring.stock.record(product: product, delta: 240, reason: .restock,
                                note: nil, saleID: nil)   // a fat-fingered 24
        try wiring.stock.adjust(product: product, countedQty: 24, note: "Salah hitung")

        let ledger = try wiring.stock.movements(for: product)
        #expect(ledger.count == 2)                  // the original still stands
        #expect(ledger.map(\.delta) == [-216, 240])
        #expect(product.stockQty == 24)
    }

    // MARK: - R-03-14

    @Test("R-03-14/AC-03-16: record against a deleted product throws and writes nothing")
    func test_R0314_AC0316_recordRefusesADeletedProduct() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)
        try wiring.catalogue.softDelete(product)

        #expect(throws: POSError.productNotFound) {
            try wiring.stock.record(product: product, delta: 5, reason: .restock,
                                    note: nil, saleID: nil)
        }
        #expect(throws: POSError.productNotFound) {
            try wiring.stock.adjust(product: product, countedQty: 5, note: "Hilang")
        }
        #expect(throws: POSError.productNotFound) {
            _ = try wiring.stock.recompute(product: product)
        }

        // Nothing new was written and the cache is untouched.
        #expect(try wiring.stock.movements(for: product).count == 1)
        #expect(product.stockQty == 24)
    }

    @Test("R-03-14: a product that was never inserted cannot move stock")
    func test_R0314_recordRefusesAnUninsertedProduct() throws {
        let wiring = try TestContainer.catalogue()
        let stranger = Fixtures.gorengan()

        #expect(throws: POSError.productNotFound) {
            try wiring.stock.record(product: stranger, delta: 1, reason: .restock,
                                    note: nil, saleID: nil)
        }
        #expect(stranger.stockQty == 0)
    }

    @Test("R-03-14 stops at reads: a deleted product's ledger stays legible (03 §8)")
    func test_R0314_readsAreNotGuarded() throws {
        let wiring = try TestContainer.catalogue()
        let product = try makeProduct(wiring)
        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)
        try wiring.catalogue.softDelete(product)

        #expect(try wiring.stock.movements(for: product).count == 1)
    }

    // MARK: - ordering

    @Test("movements(for:) is newest-first and scoped to one product")
    func test_movementsAreNewestFirstAndScoped() throws {
        let wiring = try TestContainer.catalogue()
        let chitato = try makeProduct(wiring)
        let aqua = try makeProduct(wiring, name: "Aqua 600ml", priceRp: 4_000)

        try wiring.stock.record(product: chitato, delta: 24, reason: .restock,
                                note: nil, saleID: nil)
        try wiring.stock.record(product: chitato, delta: -2, reason: .sale,
                                note: nil, saleID: UUID())
        try wiring.stock.record(product: aqua, delta: 24, reason: .restock,
                                note: nil, saleID: nil)

        #expect(try wiring.stock.movements(for: chitato).map(\.delta) == [-2, 24])
        #expect(try wiring.stock.movements(for: aqua).count == 1)
    }
}

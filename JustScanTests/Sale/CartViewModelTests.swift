//
//  CartViewModelTests.swift
//  JustScanTests
//
//  R-04-1, R-04-2, R-04-6, R-04-16 and AC-04-1/2/18 — the decisions the cashier
//  screen makes before any money moves.
//
//  The camera path is driven through `FakeScannerService`; the ViewModel cannot
//  tell the difference between it and a real `DataScannerViewController`, which
//  is the point of the module 01 contract.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct CartViewModelTests {

    private func makeModel(
        _ wiring: TestContainer.SaleWiring,
        scanner: FakeScannerService,
        contacts: ContactServicing = FakeContactService()
    ) -> CartViewModel {
        CartViewModel(catalogue: wiring.catalogue, sales: wiring.sales,
                      scanner: scanner, contacts: contacts)
    }

    private func makeProduct(
        _ wiring: TestContainer.SaleWiring,
        name: String, priceRp: Int, barcode: String, stockQty: Int
    ) throws -> Product {
        let product = try wiring.catalogue.create(name: name, priceRp: priceRp,
                                                  barcode: barcode, supplier: nil)
        if stockQty != 0 {
            try wiring.stock.record(product: product, delta: stockQty,
                                    reason: .opening, note: nil, saleID: nil)
        }
        return product
    }

    // MARK: - AC-04-1 / R-04-2 — the merge

    @Test("AC-04-1/R-04-2: scanning the same product twice yields one line at qty 2")
    func test_AC0401_R0402_sameProductTwiceIsOneLine() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let scanner = FakeScannerService(outcome: .code("8992775311011"))
        let model = makeModel(wiring, scanner: scanner)

        #expect(await model.scan() == .added)
        #expect(await model.scan() == .added)

        #expect(model.lines.count == 1)
        #expect(model.lines[0].qty == 2)
        #expect(model.lines[0].lineTotalRp == 24_000)
        #expect(model.totalRp == 24_000)
    }

    @Test("R-04-2/04 §8: the same packet scanned five times is one line at qty 5")
    func test_R0402_fiveScansOneLine() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let model = makeModel(wiring, scanner: FakeScannerService(outcome: .code("8992775311011")))

        for _ in 0..<5 { _ = await model.scan() }

        #expect(model.lines.count == 1)
        #expect(model.lines[0].qty == 5)
        #expect(model.totalRp == 60_000)
    }

    @Test("04 §10: the newest line is at the top")
    func test_newestLineIsFirst() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        _ = try makeProduct(wiring, name: "Teh Botol Sosro 350ml", priceRp: 5_000,
                            barcode: "8992772000108", stockQty: 12)
        let scanner = FakeScannerService(outcome: .code("8992775311011"))
        let model = makeModel(wiring, scanner: scanner)

        _ = await model.scan()
        scanner.outcome = .code("8992772000108")
        _ = await model.scan()

        #expect(model.lines.map(\.name)
                == ["Teh Botol Sosro 350ml", "Chitato Sapi Panggang 68g"])
        #expect(model.totalRp == 17_000)
    }

    // MARK: - AC-04-2 — the unknown barcode

    @Test("AC-04-2: an unknown barcode leaves the cart untouched and raises the banner")
    func test_AC0402_unknownBarcodeLeavesTheCartAlone() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let scanner = FakeScannerService(outcome: .code("8992775311011"))
        let model = makeModel(wiring, scanner: scanner)
        _ = await model.scan()

        scanner.outcome = .code("9999999999999")
        #expect(await model.scan() == .unknown)

        #expect(model.unknownBarcode == "9999999999999")
        #expect(model.lines.count == 1)                 // untouched
        #expect(model.totalRp == 12_000)
        #expect(model.errorMessage == nil)              // a banner, not an error

        // 04 §3.5: the operator can keep scanning other items.
        scanner.outcome = .code("8992775311011")
        #expect(await model.scan() == .added)
        #expect(model.unknownBarcode == nil)
        #expect(model.lines[0].qty == 2)
    }

    @Test("04 §8: taking 'Tambah Produk Baru' discards the cart, which the banner warns about")
    func test_addProductForUnknownBarcodeDiscardsTheCart() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let scanner = FakeScannerService(outcome: .code("8992775311011"))
        let model = makeModel(wiring, scanner: scanner)
        _ = await model.scan()
        scanner.outcome = .code("9999999999999")
        _ = await model.scan()

        #expect(model.addProductForUnknownBarcode() == .newProduct(barcode: "9999999999999"))
        #expect(model.isEmpty)
        #expect(model.unknownBarcode == nil)
        #expect(model.addProductForUnknownBarcode() == nil)
    }

    @Test("a cancelled scan changes nothing; an unavailable camera reports itself")
    func test_cancelledAndFailedScans() async throws {
        let wiring = try TestContainer.sale()
        let scanner = FakeScannerService(outcome: .cancelled)
        let model = makeModel(wiring, scanner: scanner)

        #expect(await model.scan() == .cancelled)
        #expect(model.isEmpty)
        #expect(model.errorMessage == nil)

        scanner.outcome = .unavailable
        #expect(await model.scan() == .failed)
        #expect(model.errorMessage == POSError.scannerUnavailable.message)
        #expect(model.isEmpty)
    }

    // MARK: - R-04-16 — quantity

    @Test("R-04-16: reducing a line to zero removes it")
    func test_R0416_zeroQuantityRemovesTheLine() async throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, barcode: "8992775311011",
                                      stockQty: 24)
        let model = makeModel(wiring, scanner: FakeScannerService(outcome: .code("8992775311011")))
        _ = await model.scan()

        model.setQty(3, for: chitato.id)
        #expect(model.lines[0].qty == 3)
        #expect(model.totalRp == 36_000)

        model.setQty(0, for: chitato.id)
        #expect(model.lines.isEmpty)
        #expect(model.totalRp == 0)
    }

    @Test("04 §8: removing every line returns the screen to its empty state and disables Bayar")
    func test_emptyCartDisablesBayar() async throws {
        let wiring = try TestContainer.sale()
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, barcode: "8992775311011",
                                      stockQty: 24)
        let model = makeModel(wiring, scanner: FakeScannerService(outcome: .code("8992775311011")))

        #expect(!model.canTender)
        _ = await model.scan()
        #expect(model.canTender)

        model.remove(productID: chitato.id)
        #expect(model.isEmpty)
        #expect(!model.canTender)
    }

    // MARK: - R-04-6 — the stock warning

    @Test("R-04-6/D-05: a product at zero stock warns and still sells")
    func test_R0406_zeroStockWarnsButNeverBlocks() async throws {
        let wiring = try TestContainer.sale()
        let gorengan = try makeProduct(wiring, name: "Gorengan (per pcs)", priceRp: 2_000,
                                       barcode: "9990000000001", stockQty: 0)
        let chitato = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g",
                                      priceRp: 12_000, barcode: "8992775311011",
                                      stockQty: 24)
        let scanner = FakeScannerService(outcome: .code("9990000000001"))
        let model = makeModel(wiring, scanner: scanner)

        _ = await model.scan()
        scanner.outcome = .code("8992775311011")
        _ = await model.scan()

        #expect(model.isOutOfStock(productID: gorengan.id))
        #expect(!model.isOutOfStock(productID: chitato.id))
        #expect(model.canTender)                        // never blocked

        #expect(model.tender(method: .cash, cashReceivedRp: 20_000))
        #expect(gorengan.stockQty == -1)
    }

    // MARK: - AC-04-18 — the reset

    @Test("AC-04-18: after tender the cart is empty and the screen is interactive at once")
    func test_AC0418_tenderResetsTheCart() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let model = makeModel(wiring, scanner: FakeScannerService(outcome: .code("8992775311011")))
        _ = await model.scan()
        _ = await model.scan()

        let started = Date()
        #expect(model.tender(method: .cash, cashReceivedRp: 50_000))
        let elapsed = Date().timeIntervalSince(started)

        // Synchronous — the reset is not waiting on the success screen, which
        // sits on top and dismisses itself after three seconds (04 §3.6).
        #expect(elapsed < 1.0)
        #expect(model.isEmpty)
        #expect(model.totalRp == 0)
        #expect(!model.canTender)
        #expect(model.completedSale?.changeRp == 26_000)   // 50.000 − 24.000
        #expect(model.errorMessage == nil)

        model.dismissSuccess()
        #expect(model.completedSale == nil)
    }

    @Test("a failed tender keeps the cart exactly as the operator left it")
    func test_failedTenderKeepsTheCart() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let model = makeModel(wiring, scanner: FakeScannerService(outcome: .code("8992775311011")))
        _ = await model.scan()
        _ = await model.scan()

        // Cash below the total: the service-level guard behind a disabled
        // button (R-04-8).
        #expect(!model.tender(method: .cash, cashReceivedRp: 10_000))

        #expect(model.errorMessage == POSError.insufficientCash(shortfallRp: 14_000).message)
        #expect(model.lines.count == 1)
        #expect(model.lines[0].qty == 2)
        #expect(model.completedSale == nil)

        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    @Test("R-04-1: an attached customer reaches the sale, and the field clears for the next one")
    func test_R0401_customerTravelsWithTheTender() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let ibuSari = ContactRef(id: "ABC-123", name: "Ibu Sari")
        let contacts = FakeContactService(pick: .contact(ibuSari))
        let model = makeModel(wiring,
                              scanner: FakeScannerService(outcome: .code("8992775311011")),
                              contacts: contacts)

        _ = await model.scan()
        await model.customerField.pick()
        #expect(model.customerField.ref == ibuSari)

        #expect(model.tender(method: .qris, cashReceivedRp: nil))
        #expect(model.completedSale?.customer == ibuSari)
        // The next customer is a different customer.
        #expect(model.customerField.ref == nil)
    }

    // MARK: - R-04-1 — discard

    @Test("R-04-1: discarding the cart writes nothing, because nothing was written")
    func test_R0401_discardIsFree() async throws {
        let wiring = try TestContainer.sale()
        _ = try makeProduct(wiring, name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
                            barcode: "8992775311011", stockQty: 24)
        let model = makeModel(wiring, scanner: FakeScannerService(outcome: .code("8992775311011")))
        _ = await model.scan()
        _ = await model.scan()

        model.discard()

        #expect(model.isEmpty)
        let observer = ModelContext(wiring.container)
        #expect(try observer.fetch(FetchDescriptor<Sale>()).isEmpty)
        #expect(try observer.fetch(FetchDescriptor<SaleLine>()).isEmpty)
    }
}

//
//  CatalogueViewModelTests.swift
//  JustScanTests
//
//  The scan-to-add pivot (03 §3) and the R-03-8 warning. These are ViewModel
//  decisions, not service rules, so they are pinned here — views themselves are
//  never tested (CONVENTIONS.md).
//

import Foundation
import Testing
@testable import JustScan

@MainActor
struct CatalogueViewModelTests {

    // MARK: - AC-03-1 / AC-03-2 — the pivot

    @Test("AC-03-1: scanning a known barcode opens that product and creates nothing")
    func test_AC0301_knownBarcodeOpensTheExistingProduct() async throws {
        let wiring = try TestContainer.catalogue()
        let chitato = try wiring.catalogue.create(
            name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
            barcode: "8992775311011", supplier: nil
        )
        let model = ProductListViewModel(
            catalogue: wiring.catalogue,
            scanner: FakeScannerService(outcome: .code("8992775311011"))
        )

        let route = await model.scan()

        #expect(route == .detail(chitato))
        #expect(try wiring.catalogue.all().count == 1)   // nothing created
        #expect(model.errorMessage == nil)
    }

    @Test("AC-03-2: an unknown barcode opens the form with the code prefilled")
    func test_AC0302_unknownBarcodeOpensAPrefilledForm() async throws {
        let wiring = try TestContainer.catalogue()
        let model = ProductListViewModel(
            catalogue: wiring.catalogue,
            scanner: FakeScannerService(outcome: .code("8992772000108"))
        )

        let route = await model.scan()
        #expect(route == .newProduct(barcode: "8992772000108"))

        // Prefilled and locked: the form has no way to change it, and
        // `CatalogueServicing.update` has no barcode parameter.
        let form = ProductFormViewModel(
            mode: .create(barcode: "8992772000108"),
            catalogue: wiring.catalogue,
            contacts: FakeContactService()
        )
        #expect(form.barcode == "8992772000108")
        #expect(form.barcodeLabel == "8992772000108")
    }

    @Test("03 §3.2: a cancelled scan changes nothing")
    func test_cancelledScanChangesNothing() async throws {
        let wiring = try TestContainer.catalogue()
        let model = ProductListViewModel(
            catalogue: wiring.catalogue,
            scanner: FakeScannerService(outcome: .cancelled)
        )

        #expect(await model.scan() == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("An unavailable scanner reports its Indonesian message, not a crash")
    func test_unavailableScannerIsReported() async throws {
        let wiring = try TestContainer.catalogue()
        let model = ProductListViewModel(
            catalogue: wiring.catalogue,
            scanner: FakeScannerService(outcome: .unavailable)
        )

        #expect(await model.scan() == nil)
        #expect(model.errorMessage == POSError.scannerUnavailable.message)
    }

    @Test("A soft-deleted product's barcode scans as unknown (03 §8)")
    func test_deletedProductsBarcodeScansAsUnknown() async throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(
            name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
            barcode: "8992775311011", supplier: nil
        )
        try wiring.catalogue.softDelete(product)

        let model = ProductListViewModel(
            catalogue: wiring.catalogue,
            scanner: FakeScannerService(outcome: .code("8992775311011"))
        )
        #expect(await model.scan() == .newProduct(barcode: "8992775311011"))
    }

    // MARK: - AC-03-7 / R-03-8

    @Test("AC-03-7/R-03-8: an internal code warns, and proceeding still creates the product")
    func test_AC0307_internalCodeWarnsButDoesNotBlock() async throws {
        let wiring = try TestContainer.catalogue()
        let model = ProductListViewModel(
            catalogue: wiring.catalogue,
            scanner: FakeScannerService(outcome: .code(Fixtures.internalCode))
        )

        #expect(await model.scan() == .newProduct(barcode: Fixtures.internalCode))

        let form = ProductFormViewModel(
            mode: .create(barcode: Fixtures.internalCode),
            catalogue: wiring.catalogue,
            contacts: FakeContactService()
        )
        #expect(form.internalCodeWarning == """
            Kode ini kode toko/timbangan, bukan barcode produk. \
            Barcode-nya bisa berbeda tiap kemasan.
            """)

        // The warning is a banner, not a gate.
        form.name = "Bawang Merah"
        form.priceRp = 30_000
        let saved = try #require(form.save())
        #expect(saved.barcode == Fixtures.internalCode)
        #expect(try wiring.catalogue.all().count == 1)
    }

    @Test("R-03-8: a GTIN and a barcode-less product raise no warning")
    func test_R0308_onlyInternalCodesWarn() throws {
        let wiring = try TestContainer.catalogue()

        let gtin = ProductFormViewModel(mode: .create(barcode: "8992775311011"),
                                        catalogue: wiring.catalogue,
                                        contacts: FakeContactService())
        #expect(gtin.internalCodeWarning == nil)

        let none = ProductFormViewModel(mode: .create(barcode: nil),
                                        catalogue: wiring.catalogue,
                                        contacts: FakeContactService())
        #expect(none.internalCodeWarning == nil)
        #expect(none.barcodeLabel == "Tanpa barcode")
    }

    // MARK: - The form

    @Test("§11: a barcode collision names the product holding the code")
    func test_collisionMessageNamesTheExistingProduct() throws {
        let wiring = try TestContainer.catalogue()
        let existing = try wiring.catalogue.create(
            name: "Chitato Sapi Panggang 68g", priceRp: 12_000,
            barcode: "8992775311011", supplier: nil
        )

        let form = ProductFormViewModel(mode: .create(barcode: "8992775311011"),
                                        catalogue: wiring.catalogue,
                                        contacts: FakeContactService())
        form.name = "Chitato Rasa Keju 68g"
        form.priceRp = 12_000

        #expect(form.save() == nil)
        #expect(form.errorMessage == "Barcode ini sudah dipakai Chitato Sapi Panggang 68g.")
        #expect(form.conflicting == existing)   // the "Lihat" target
    }

    @Test("The Save button is disabled until name and price are valid (03 §8)")
    func test_saveIsDisabledUntilTheFormIsValid() throws {
        let wiring = try TestContainer.catalogue()
        let form = ProductFormViewModel(mode: .create(barcode: nil),
                                        catalogue: wiring.catalogue,
                                        contacts: FakeContactService())

        #expect(!form.canSave)
        form.name = "  "
        #expect(!form.canSave)
        form.name = "Gorengan (per pcs)"
        #expect(!form.canSave)          // price is still zero (R-03-5)
        form.priceRp = 2_000
        #expect(form.canSave)
    }

    @Test("The form carries the supplier through to both product columns")
    func test_formAttachesTheSupplierToTheProduct() async throws {
        let wiring = try TestContainer.catalogue()
        let budi = ContactRef(id: "ABC-123", name: "Toko Grosir Budi")
        let form = ProductFormViewModel(
            mode: .create(barcode: nil),
            catalogue: wiring.catalogue,
            contacts: FakeContactService(pick: .contact(budi))
        )
        form.name = "Chitato Sapi Panggang 68g"
        form.priceRp = 12_000
        await form.supplierField.pick()

        let saved = try #require(form.save())
        #expect(saved.supplier == budi)
    }

    @Test("Edit mode loads the product and writes back through the service")
    func test_editModeUpdatesTheProduct() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: 4_000,
                                                  barcode: "8886008101053", supplier: nil)

        let form = ProductFormViewModel(mode: .edit(product),
                                        catalogue: wiring.catalogue,
                                        contacts: FakeContactService())
        #expect(form.name == "Aqua 600ml")
        #expect(form.priceRp == 4_000)
        #expect(form.barcode == "8886008101053")
        #expect(form.title == "Ubah Produk")

        form.priceRp = 4_500
        #expect(form.save() === product)
        #expect(product.priceRp == 4_500)
    }

    // MARK: - The list

    @Test("The list loads name-sorted and filters through search()")
    func test_listLoadsAndFilters() throws {
        let wiring = try TestContainer.catalogue()
        for name in ["Teh Botol Sosro 350ml", "Aqua 600ml", "Chitato Sapi Panggang 68g"] {
            _ = try wiring.catalogue.create(name: name, priceRp: 5_000,
                                            barcode: nil, supplier: nil)
        }
        let model = ProductListViewModel(catalogue: wiring.catalogue,
                                         scanner: FakeScannerService(outcome: .cancelled))

        model.load()
        #expect(model.products.map(\.name) == [
            "Aqua 600ml", "Chitato Sapi Panggang 68g", "Teh Botol Sosro 350ml"
        ])
        #expect(!model.isEmpty)

        model.query = "aqua"
        model.load()
        #expect(model.products.map(\.name) == ["Aqua 600ml"])
    }

    @Test("An empty catalogue is empty; an empty search result is not")
    func test_emptyStateIsDistinctFromAnEmptySearch() throws {
        let wiring = try TestContainer.catalogue()
        let model = ProductListViewModel(catalogue: wiring.catalogue,
                                         scanner: FakeScannerService(outcome: .cancelled))
        model.load()
        #expect(model.isEmpty)

        _ = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: 4_000,
                                        barcode: nil, supplier: nil)
        model.query = "chitato"
        model.load()
        #expect(model.products.isEmpty)
        #expect(!model.isEmpty)     // a search miss is not "belum ada produk"
    }

    // MARK: - The detail screen

    @Test("Detail actions route through the services and reload the ledger")
    func test_detailAddsAdjustsAndRecomputes() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000, barcode: nil, supplier: nil)
        let model = ProductDetailViewModel(product: product,
                                           catalogue: wiring.catalogue,
                                           stock: wiring.stock,
                                           contacts: FakeContactService())
        model.load()
        #expect(model.movements.isEmpty)

        model.addStock(24)
        #expect(product.stockQty == 24)
        #expect(model.movements.count == 1)
        #expect(model.movements[0].reason == .restock)

        model.adjust(countedQty: 21, note: "Kedaluwarsa")
        #expect(product.stockQty == 21)
        #expect(model.movements.count == 2)

        model.recompute()
        #expect(model.recomputeResult == .init(before: 21, after: 21))
        #expect(model.recomputeResult?.matches == true)
        #expect(model.errorMessage == nil)
    }

    @Test("Recompute surfaces a drifted cache rather than hiding it")
    func test_recomputeSurfacesADriftedCache() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000, barcode: nil, supplier: nil)
        try wiring.stock.record(product: product, delta: 24, reason: .restock,
                                note: nil, saleID: nil)
        product.stockQty = 99   // drift, as a cache bug would produce

        let model = ProductDetailViewModel(product: product,
                                           catalogue: wiring.catalogue,
                                           stock: wiring.stock,
                                           contacts: FakeContactService())
        model.recompute()

        #expect(model.recomputeResult == .init(before: 99, after: 24))
        #expect(model.recomputeResult?.matches == false)
    }

    @Test("An adjustment that changes nothing writes nothing and reports no error")
    func test_noOpAdjustmentIsSilentlyFine() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: 4_000,
                                                  barcode: nil, supplier: nil)
        let model = ProductDetailViewModel(product: product,
                                           catalogue: wiring.catalogue,
                                           stock: wiring.stock,
                                           contacts: FakeContactService())

        model.adjust(countedQty: 0, note: "Salah hitung")

        #expect(model.movements.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("Delete is soft, and the screen pops rather than rendering a dead row")
    func test_deleteIsSoftAndSignalsTheView() throws {
        let wiring = try TestContainer.catalogue()
        let product = try wiring.catalogue.create(name: "Aqua 600ml", priceRp: 4_000,
                                                  barcode: "8886008101053", supplier: nil)
        let model = ProductDetailViewModel(product: product,
                                           catalogue: wiring.catalogue,
                                           stock: wiring.stock,
                                           contacts: FakeContactService())

        model.delete()

        #expect(model.isDeleted)
        #expect(product.deletedAt != nil)
        #expect(try wiring.catalogue.all().isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("Detaching a supplier on the detail screen clears both columns")
    func test_detailPersistsASupplierChange() throws {
        let wiring = try TestContainer.catalogue()
        let budi = ContactRef(id: "ABC-123", name: "Toko Grosir Budi")
        let product = try wiring.catalogue.create(name: "Chitato Sapi Panggang 68g",
                                                  priceRp: 12_000, barcode: nil, supplier: budi)
        let model = ProductDetailViewModel(product: product,
                                           catalogue: wiring.catalogue,
                                           stock: wiring.stock,
                                           contacts: FakeContactService())

        model.supplierField.detach()
        model.saveSupplier()

        #expect(product.supplierContactID == nil)
        #expect(product.supplierName == nil)
    }
}

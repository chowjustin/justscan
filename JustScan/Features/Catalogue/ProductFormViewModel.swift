//
//  ProductFormViewModel.swift
//  JustScan
//
//  New and edit are one form (03 §10), because the fields are the same and the
//  only difference is whether a barcode is already fixed.
//
//  It holds the `ContactFieldViewModel` for the supplier: module 02 ships the
//  row, the host owns the instance, and this reads `.ref` at save time — which
//  is how two columns reach `Product.supplier` without this module knowing that
//  Contacts exists.
//

import Foundation

@MainActor
@Observable
final class ProductFormViewModel {
    enum Mode {
        case create(barcode: String?)
        case edit(Product)
    }

    var name: String
    var priceRp: Int

    /// Shown, never editable (03 §10). A code is the identity a scan resolves,
    /// so it is fixed at creation — `CatalogueServicing.update` has no barcode
    /// parameter by design.
    let barcode: String?

    let supplierField: ContactFieldViewModel

    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// The product already using this barcode, when a save collided (§11).
    /// The view offers "Lihat" to open it.
    private(set) var conflicting: Product?

    private let mode: Mode
    private let catalogue: CatalogueServicing

    init(mode: Mode, catalogue: CatalogueServicing, contacts: ContactServicing) {
        self.mode = mode
        self.catalogue = catalogue

        switch mode {
        case .create(let barcode):
            self.name = ""
            self.priceRp = 0
            self.barcode = barcode
            self.supplierField = ContactFieldViewModel(contacts: contacts)
        case .edit(let product):
            self.name = product.name
            self.priceRp = product.priceRp
            self.barcode = product.barcode
            self.supplierField = ContactFieldViewModel(contacts: contacts,
                                                       ref: product.supplier)
        }
    }

    var title: String {
        switch mode {
        case .create: return "Produk Baru"
        case .edit:   return "Ubah Produk"
        }
    }

    var barcodeLabel: String {
        barcode ?? "Tanpa barcode"
    }

    /// R-03-8. A store or scale code encodes weight or price in its digits, so
    /// the same product yields a different code on every package. The operator
    /// may proceed anyway — this is a banner, never a blocking alert.
    var internalCodeWarning: String? {
        guard let barcode, BarcodeKind.of(barcode) == .internalCode else { return nil }
        return "Kode ini kode toko/timbangan, bukan barcode produk. "
             + "Barcode-nya bisa berbeda tiap kemasan."
    }

    /// Cheap feedback only. The real guard is R-03-2, inside the service.
    var canSave: Bool {
        !isSaving
        && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && priceRp > 0
    }

    /// Returns the saved product on success, nil on failure. The double-tap
    /// guard here is a courtesy; two taps that race past it still collide on
    /// the service's uniqueness check (03 §8).
    func save() -> Product? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }

        errorMessage = nil
        conflicting = nil

        do {
            switch mode {
            case .create:
                return try catalogue.create(name: name, priceRp: priceRp,
                                            barcode: barcode,
                                            supplier: supplierField.ref)
            case .edit(let product):
                try catalogue.update(product, name: name, priceRp: priceRp,
                                     supplier: supplierField.ref)
                return product
            }
        } catch POSError.barcodeAlreadyExists(let productID) {
            // §11: name the product that owns the code. A generic "sudah
            // dipakai produk lain" makes the operator hunt for it themselves.
            let existing = (try? catalogue.all())?.first { $0.id == productID }
            conflicting = existing
            errorMessage = existing.map { "Barcode ini sudah dipakai \($0.name)." }
                ?? POSError.barcodeAlreadyExists(productID: productID).message
            return nil
        } catch {
            errorMessage = (error as? POSError)?.message
                ?? POSError.persistenceFailed(String(describing: error)).message
            return nil
        }
    }

    func dismissError() {
        errorMessage = nil
        conflicting = nil
    }
}

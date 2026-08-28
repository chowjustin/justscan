//
//  ProductDetailViewModel.swift
//  JustScan
//
//  Everything the detail screen can do to a product, and nothing it can do
//  directly. Quantity changes go through `StockServicing`; field edits go
//  through `CatalogueServicing`. This type never touches `stockQty` itself
//  (R-03-6).
//

import Foundation

@MainActor
@Observable
final class ProductDetailViewModel {
    /// What "Hitung Ulang dari Riwayat" found. A difference is a cache bug and
    /// is surfaced, never hidden (03 §3).
    struct RecomputeResult: Equatable {
        let before: Int
        let after: Int
        var matches: Bool { before == after }
    }

    let product: Product
    let supplierField: ContactFieldViewModel

    private(set) var movements: [StockMovement] = []
    private(set) var errorMessage: String?
    private(set) var recomputeResult: RecomputeResult?

    /// Set once the product is soft-deleted, so the view can pop rather than
    /// render a row that no longer exists.
    private(set) var isDeleted = false

    private let catalogue: CatalogueServicing
    private let stock: StockServicing

    init(product: Product,
         catalogue: CatalogueServicing,
         stock: StockServicing,
         contacts: ContactServicing) {
        self.product = product
        self.catalogue = catalogue
        self.stock = stock
        self.supplierField = ContactFieldViewModel(contacts: contacts,
                                                   ref: product.supplier)
    }

    func load() {
        do {
            movements = try stock.movements(for: product)
        } catch {
            movements = []
            report(error)
        }
    }

    /// 03 §3 "Add stock". Always a `.restock`, never an adjustment — the
    /// operator is telling us goods arrived, not correcting a count.
    func addStock(_ qty: Int) {
        run { try stock.record(product: product, delta: qty, reason: .restock,
                               note: nil, saleID: nil) }
    }

    /// The operator supplies the **counted** quantity; the service does the
    /// arithmetic. Counting the same number twice writes nothing.
    func adjust(countedQty: Int, note: String) {
        run { try stock.adjust(product: product, countedQty: countedQty, note: note) }
    }

    func recompute() {
        let before = product.stockQty
        do {
            let after = try stock.recompute(product: product)
            recomputeResult = RecomputeResult(before: before, after: after)
            load()
        } catch {
            report(error)
        }
    }

    /// Persists a supplier picked or detached on this screen. `ContactField` is
    /// an editor, not a label (03 §10), so a change here has to land on both
    /// columns of the product.
    func saveSupplier() {
        run(reload: false) {
            try catalogue.update(product, name: product.name,
                                 priceRp: product.priceRp,
                                 supplier: supplierField.ref)
        }
    }

    /// Soft delete (R-03-12). The product vanishes from the catalogue and from
    /// scan lookup; its movements and any past sale lines are untouched.
    func delete() {
        run(reload: false) {
            try catalogue.softDelete(product)
            isDeleted = true
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissRecomputeResult() {
        recomputeResult = nil
    }

    private func run(reload: Bool = true, _ operation: () throws -> Void) {
        errorMessage = nil
        do {
            try operation()
            if reload { load() }
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? POSError)?.message
            ?? POSError.persistenceFailed(String(describing: error)).message
    }
}

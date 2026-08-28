//
//  CartViewModel.swift
//  JustScan
//
//  The cashier screen's state, and every decision it makes. The view below it
//  renders and taps; it decides nothing (CONVENTIONS.md, layering).
//
//  The cart lives here and only here (R-04-1, D-14). Nothing on this type can
//  reach a `ModelContext`: the draft is a value, and the only writes go through
//  `SaleServicing`.
//

import Foundation

@MainActor
@Observable
final class CartViewModel {
    /// Where the "Tambah Produk Baru" banner sends the operator. The view owns
    /// the navigation stack; this type only decides the destination.
    enum Route: Hashable {
        case newProduct(barcode: String)
    }

    /// What a scan did, so the view knows which haptic to fire (04 §10).
    enum ScanOutcome: Equatable {
        case added
        case unknown
        case cancelled
        case failed
    }

    private(set) var draft = SaleDraft()

    /// The code the last scan could not resolve. Drives the inline banner; the
    /// cart is untouched and the operator can keep scanning (04 §3.5).
    private(set) var unknownBarcode: String?

    private(set) var errorMessage: String?

    /// Set for exactly as long as the success screen is up (04 §3.6).
    private(set) var completedSale: Sale?

    /// Stock as it stood when each product was scanned, for the R-04-6 warning
    /// chip. It is deliberately **not** on `DraftLine`: a line is a price and a
    /// quantity quoted to a customer, and stock is neither.
    private var stockByProductID: [UUID: Int] = [:]

    /// Module 02's shared row, embedded as "Pelanggan" (04 §3.9).
    let customerField: ContactFieldViewModel

    private let catalogue: CatalogueServicing
    private let sales: SaleServicing
    private let scanner: ScannerServicing

    init(catalogue: CatalogueServicing,
         sales: SaleServicing,
         scanner: ScannerServicing,
         contacts: ContactServicing) {
        self.catalogue = catalogue
        self.sales = sales
        self.scanner = scanner
        self.customerField = ContactFieldViewModel(contacts: contacts)
    }

    // MARK: - Reading

    var lines: [DraftLine] { draft.lines }
    var totalRp: Int { draft.totalRp }
    var isEmpty: Bool { draft.isEmpty }

    /// Bayar is disabled on an empty cart. `emptyCart` is still the
    /// service-level guard behind it — the button is a courtesy, not the rule
    /// (04 §3, R-04-7).
    var canTender: Bool { !draft.isEmpty }

    /// R-04-6 and D-05: a warning, never a block. Zero counts, because a shop
    /// that says "0" is already out of stock.
    func isOutOfStock(productID: UUID) -> Bool {
        (stockByProductID[productID] ?? 0) <= 0
    }

    // MARK: - Scanning

    /// 04 §3, steps 2–6. One scan either grows the cart or explains why it
    /// could not; it never opens a dialog and never loses what is already
    /// there.
    func scan() async -> ScanOutcome {
        errorMessage = nil
        do {
            guard let code = try await scanner.scan() else { return .cancelled }

            guard let product = try catalogue.findBy(barcode: code) else {
                unknownBarcode = code                       // AC-04-2
                return .unknown
            }

            unknownBarcode = nil
            add(product)                                    // AC-04-1
            return .added
        } catch {
            report(error)
            return .failed
        }
    }

    /// R-04-2. The price is captured here, at scan time, and never re-read: the
    /// line was quoted to the customer, so a price edited in another tab does
    /// not change it (04 §8).
    func add(_ product: Product) {
        stockByProductID[product.id] = product.stockQty
        draft.add(productID: product.id, name: product.name,
                  unitPriceRp: product.priceRp)
    }

    // MARK: - Editing

    /// R-04-16. Zero removes the line rather than leaving one that sells
    /// nothing.
    func setQty(_ qty: Int, for productID: UUID) {
        draft.setQty(qty, for: productID)
        if draft.lines.contains(where: { $0.productID == productID }) == false {
            stockByProductID[productID] = nil
        }
    }

    func remove(productID: UUID) {
        draft.remove(productID: productID)
        stockByProductID[productID] = nil
    }

    /// Discarding the cart. Nothing was persisted, so nothing is undone
    /// (R-04-1). The customer stays attached — discarding what was scanned is
    /// not the same as forgetting who is at the counter.
    func discard() {
        draft.clear()
        stockByProductID = [:]
        unknownBarcode = nil
    }

    // MARK: - Tender

    /// 04 §3, step 5. Returns true when the sale committed.
    ///
    /// The cart is emptied **only** on success, and synchronously, so the
    /// screen is ready for the next customer immediately (AC-04-18). A failed
    /// tender leaves the cart exactly as the operator left it, because
    /// re-scanning five items to recover from a save error is not a thing a
    /// shop can do at a counter.
    @discardableResult
    func tender(method: PaymentMethod, cashReceivedRp: Int?) -> Bool {
        errorMessage = nil
        do {
            let sale = try sales.complete(lines: draft.lines,
                                          method: method,
                                          cashReceivedRp: cashReceivedRp,
                                          customer: customerField.ref)
            draft.clear()
            stockByProductID = [:]
            unknownBarcode = nil
            customerField.detach()
            completedSale = sale
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Dismissal

    /// The banner's "Tambah Produk Baru". Taking it discards the cart and
    /// leaves the screen — the banner says so, because there is no
    /// cart-preserving detour and building one is deferred (04 §8).
    func addProductForUnknownBarcode() -> Route? {
        guard let code = unknownBarcode else { return nil }
        discard()
        return .newProduct(barcode: code)
    }

    func dismissUnknownBarcode() {
        unknownBarcode = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissSuccess() {
        completedSale = nil
    }

    private func report(_ error: Error) {
        errorMessage = (error as? POSError)?.message
            ?? POSError.persistenceFailed(String(describing: error)).message
    }
}

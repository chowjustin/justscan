//
//  ProductListViewModel.swift
//  JustScan
//
//  The pivot flow lives here (03 §3): one scan either opens the product the
//  operator already owns, or opens a prefilled form for one they do not. Never
//  both, never a duplicate, never an error dialog for a code we simply have not
//  seen before.
//

import Foundation

@MainActor
@Observable
final class ProductListViewModel {
    /// Where a scan, or a tap, sends the operator next. The view owns the
    /// navigation stack; this type only decides the destination.
    enum Route: Hashable {
        case detail(Product)
        case newProduct(barcode: String?)
        case edit(Product)
    }

    private(set) var products: [Product] = []
    private(set) var errorMessage: String?

    /// Bound to `.searchable`. The view calls `load()` when it changes.
    var query: String = ""

    var isEmpty: Bool { products.isEmpty && query.isEmpty }

    private let catalogue: CatalogueServicing
    private let scanner: ScannerServicing

    init(catalogue: CatalogueServicing, scanner: ScannerServicing) {
        self.catalogue = catalogue
        self.scanner = scanner
    }

    func load() {
        do {
            products = try catalogue.search(query)
        } catch {
            products = []
            report(error)
        }
    }

    /// 03 §3, steps 1–5. Returns nil when the operator cancelled — that is an
    /// ordinary outcome and changes nothing.
    func scan() async -> Route? {
        errorMessage = nil
        do {
            guard let code = try await scanner.scan() else { return nil }

            if let existing = try catalogue.findBy(barcode: code) {
                return .detail(existing)                // AC-03-1
            }
            return .newProduct(barcode: code)           // AC-03-2
        } catch {
            report(error)
            return nil
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func report(_ error: Error) {
        errorMessage = (error as? POSError)?.message
            ?? POSError.persistenceFailed(String(describing: error)).message
    }
}

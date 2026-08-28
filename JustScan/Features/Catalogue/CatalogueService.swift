//
//  CatalogueService.swift
//  JustScan
//
//  The product master. Every rule in 03 §4 that is not about quantity lives
//  here; quantity belongs to `StockService` and to nothing else (R-03-6).
//
//  Uniqueness is checked **inside** `create`, immediately before the insert
//  (R-03-2). A check performed only in a ViewModel is a defect, because two
//  rapid taps on Save race past it.
//

import Foundation
import OSLog

protocol CatalogueServicing {
    func create(name: String, priceRp: Int, barcode: String?,
                supplier: ContactRef?) throws -> Product
    func update(_ product: Product, name: String, priceRp: Int,
                supplier: ContactRef?) throws
    func softDelete(_ product: Product) throws
    func findBy(barcode: String) throws -> Product?    // excludes deleted
    func all() throws -> [Product]                     // excludes deleted, name-sorted
    func search(_ query: String) throws -> [Product]   // name contains, case-insensitive
}

struct CatalogueService: CatalogueServicing {
    private static let log = Logger(subsystem: "chow.JustScan", category: "catalogue")

    private let products: ProductRepository

    init(products: ProductRepository) {
        self.products = products
    }

    /// A new product always starts at `stockQty = 0` with **no** movement
    /// written. Zero stock is the absence of movements, never a movement of
    /// zero (03 §3, R-03-13).
    func create(name: String, priceRp: Int, barcode: String?,
                supplier: ContactRef?) throws -> Product {
        let cleanName = try Self.validated(name: name)
        try Self.validate(priceRp: priceRp)
        let code = Self.normalised(barcode: barcode)

        // R-03-2: inside the service call, immediately before the insert.
        // R-03-3: nil is not a value, so it cannot collide and is not checked.
        if let code, let existing = try lookUp(barcode: code) {
            throw POSError.barcodeAlreadyExists(productID: existing.id)
        }

        let now = Date()
        let product = Product(
            name: cleanName,
            priceRp: priceRp,
            barcode: code,
            createdAt: now,
            updatedAt: now
        )
        product.supplier = supplier   // R-02-5: both columns move together

        products.insert(product)
        try commit()

        Self.log.info("created product \(product.id, privacy: .public)")
        return product
    }

    /// Name, price, and supplier only.
    ///
    /// `barcode` is deliberately absent from the signature (03 §7): a code is
    /// the identity a scan resolves, so it is set once at creation and shown
    /// locked thereafter (03 §10).
    func update(_ product: Product, name: String, priceRp: Int,
                supplier: ContactRef?) throws {
        try requireLive(product)

        let cleanName = try Self.validated(name: name)
        try Self.validate(priceRp: priceRp)

        product.name = cleanName
        product.priceRp = priceRp
        product.supplier = supplier
        product.updatedAt = Date()

        try commit()
        Self.log.info("updated product \(product.id, privacy: .public)")
    }

    /// Soft delete, always (R-03-12). The row survives so past sales and the
    /// movement ledger stay readable; it simply stops being findable.
    func softDelete(_ product: Product) throws {
        try requireLive(product)

        let now = Date()
        product.deletedAt = now
        product.updatedAt = now

        try commit()
        Self.log.info("soft-deleted product \(product.id, privacy: .public)")
    }

    func findBy(barcode: String) throws -> Product? {
        guard let code = Self.normalised(barcode: barcode) else { return nil }
        return try lookUp(barcode: code)
    }

    func all() throws -> [Product] {
        do {
            return try products.all()
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }

    /// A blank query is not a filter — it is the unfiltered list, which is what
    /// clearing the search field must show.
    func search(_ query: String) throws -> [Product] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try all() }
        return try all().filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    // MARK: - Rules

    /// R-03-4. Trimmed, 1–80 characters. Names are **not** unique — two
    /// suppliers' "Kopi Hitam" may legitimately coexist.
    private static func validated(name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmed.count) else {
            throw POSError.validationFailed(field: "name")
        }
        return trimmed
    }

    /// R-03-5. Free items are not a case this app supports.
    private static func validate(priceRp: Int) throws {
        guard priceRp > 0 else { throw POSError.validationFailed(field: "price") }
    }

    /// A barcode is either a code or absent. An empty string is neither, so it
    /// becomes `nil` rather than a value that would collide with itself
    /// (R-03-3).
    private static func normalised(barcode: String?) -> String? {
        guard let trimmed = barcode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// R-03-14. Matches `StockService.requireLive` deliberately: the same rule
    /// guards every write path in this module.
    private func requireLive(_ product: Product) throws {
        guard product.deletedAt == nil else { throw POSError.productNotFound }

        let live: Product?
        do {
            live = try products.find(id: product.id)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
        guard live != nil else { throw POSError.productNotFound }
    }

    // MARK: - Persistence

    private func lookUp(barcode: String) throws -> Product? {
        do {
            return try products.findBy(barcode: barcode)
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }

    private func commit() throws {
        do {
            try products.save()
        } catch {
            throw POSError.persistenceFailed(String(describing: error))
        }
    }
}

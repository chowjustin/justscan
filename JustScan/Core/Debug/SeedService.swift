//
//  SeedService.swift
//  JustScan
//
//  DEBUG only. Real Indonesian products with real barcodes and plausible
//  prices, so every screen has something to render on a fresh install
//  (foundations §9).
//
//  Runs only into an empty store and is idempotent.
//

#if DEBUG

import Foundation
import OSLog

struct SeedService {
    private static let log = Logger(subsystem: "chow.JustScan", category: "seed")

    private let products: ProductRepository
    private let movements: StockMovementRepository

    init(products: ProductRepository, movements: StockMovementRepository) {
        self.products = products
        self.movements = movements
    }

    /// One row per foundations §9. `openingStock == 0` gets **no** movement:
    /// zero stock is the absence of movements, never a movement of zero
    /// (R-03-9, R-03-13).
    private struct SeedProduct {
        let name: String
        let barcode: String?
        let priceRp: Int
        let openingStock: Int
        let supplier: (id: String, name: String)?
    }

    /// Seed suppliers pair the name with a **synthetic** identifier so both
    /// D-11 columns are populated. `ContactService.resolve(id:)` returns nil for
    /// these, permanently — seed data is DEBUG-only and never reaches a shop
    /// (foundations §9).
    private static let budi = (id: "seed-toko-grosir-budi", name: "Toko Grosir Budi")

    private static let catalogue: [SeedProduct] = [
        SeedProduct(name: "Chitato Sapi Panggang 68g", barcode: "8992775311011",
                    priceRp: 12_000, openingStock: 24, supplier: budi),
        SeedProduct(name: "Teh Botol Sosro 350ml", barcode: "8992772000108",
                    priceRp: 5_000, openingStock: 12, supplier: budi),
        SeedProduct(name: "Indomie Goreng 85g", barcode: "8998866200608",
                    priceRp: 3_500, openingStock: 40, supplier: budi),
        SeedProduct(name: "Aqua 600ml", barcode: "8886008101053",
                    priceRp: 4_000, openingStock: 24, supplier: nil),
        // The barcode-less, stock-less case, on purpose. Every screen must
        // handle it without a special path (foundations §9).
        SeedProduct(name: "Gorengan (per pcs)", barcode: nil,
                    priceRp: 2_000, openingStock: 0, supplier: nil)
    ]

    /// Idempotent: a non-empty store is left exactly as it is.
    /// One `save()` for the whole operation (CONVENTIONS.md).
    func load() throws {
        guard try products.all().isEmpty else {
            Self.log.info("Store is not empty, skipping seed.")
            return
        }

        let now = Date()

        for row in Self.catalogue {
            let product = Product(
                name: row.name,
                priceRp: row.priceRp,
                stockQty: row.openingStock,
                barcode: row.barcode,
                supplierContactID: row.supplier?.id,
                supplierName: row.supplier?.name,
                createdAt: now,
                updatedAt: now
            )
            products.insert(product)

            guard row.openingStock > 0 else { continue }

            movements.insert(
                StockMovement(
                    product: product,
                    delta: row.openingStock,
                    reason: .opening,
                    createdAt: now
                )
            )
        }

        try products.save()
        Self.log.info("Seeded \(Self.catalogue.count, privacy: .public) products.")
    }
}

#endif

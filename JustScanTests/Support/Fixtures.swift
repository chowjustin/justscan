//
//  Fixtures.swift
//  JustScanTests
//
//  The foundations §9 products, so a test that needs "a product" does not have
//  to invent one. Real barcodes and real prices — a test written against
//  made-up data proves less than one written against the data the app ships.
//

import Foundation
@testable import JustScan

enum Fixtures {
    /// Has a barcode, has stock, has a supplier.
    static func chitato(stockQty: Int = 0) -> Product {
        Product(
            name: "Chitato Sapi Panggang 68g",
            priceRp: 12_000,
            stockQty: stockQty,
            barcode: "8992775311011",
            supplierContactID: "seed-toko-grosir-budi",
            supplierName: "Toko Grosir Budi"
        )
    }

    static func tehBotol(stockQty: Int = 0) -> Product {
        Product(
            name: "Teh Botol Sosro 350ml",
            priceRp: 5_000,
            stockQty: stockQty,
            barcode: "8992772000108"
        )
    }

    /// The barcode-less, stock-less case. Every path must handle it without a
    /// special branch (foundations §9).
    static func gorengan() -> Product {
        Product(name: "Gorengan (per pcs)", priceRp: 2_000)
    }

    /// A 13-digit code with a `20` prefix — the R-03-8 / AC-03-7 case.
    static let internalCode = "2011234501234"
}

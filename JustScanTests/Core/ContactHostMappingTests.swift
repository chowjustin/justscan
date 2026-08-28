//
//  ContactHostMappingTests.swift
//  JustScanTests
//
//  Module 02 persists nothing, but it owns the shape of what the hosts store
//  (R-02-1, R-02-5, D-11). These run the pairing through a real in-memory store,
//  because "two columns land together" is only true if it survives a save.
//
//  AC-02-8 is proved here at the repository layer; module 03 re-proves it
//  through `CatalogueService.create`, which does not exist yet.
//

import Foundation
import SwiftData
import Testing
@testable import JustScan

@MainActor
struct ContactHostMappingTests {
    private static let budi = ContactRef(id: "ABC-123", name: "Budi Santoso")

    @Test("AC-02-8: a product saves with no supplier, leaving both columns nil")
    func test_AC0208_productSavesWithNoSupplier() throws {
        let (_, _, products, _) = try TestContainer.repositories()

        let product = Product(name: "Gorengan (per pcs)", priceRp: 2000)
        products.insert(product)
        try products.save()

        let saved = try #require(try products.all().first)
        #expect(saved.supplierContactID == nil)
        #expect(saved.supplierName == nil)
        #expect(saved.supplier == nil)
    }

    @Test("R-02-1: a supplier round-trips through the store as two columns")
    func test_R0201_supplierRoundTripsAsTwoColumns() throws {
        let (_, _, products, _) = try TestContainer.repositories()

        let product = Product(name: "Chitato Sapi Panggang 68g", priceRp: 12000)
        product.supplier = Self.budi
        products.insert(product)
        try products.save()

        let saved = try #require(try products.all().first)
        #expect(saved.supplierContactID == "ABC-123")
        #expect(saved.supplierName == "Budi Santoso")
        #expect(saved.supplier == Self.budi)
    }

    @Test("R-02-5: clearing a supplier clears both columns")
    func test_R0205_clearingSupplierClearsBothColumns() throws {
        let (_, _, products, _) = try TestContainer.repositories()

        let product = Product(name: "Aqua 600ml", priceRp: 4000)
        product.supplier = Self.budi
        products.insert(product)
        try products.save()

        product.supplier = nil
        try products.save()

        let saved = try #require(try products.all().first)
        #expect(saved.supplierContactID == nil)
        #expect(saved.supplierName == nil)
    }

    @Test("R-02-5: a row carrying only an identifier reads as having no supplier")
    func test_R0205_halfPopulatedRowReadsAsAbsent() {
        let product = Product(name: "Teh Botol Sosro 350ml", priceRp: 5000)
        product.supplierContactID = "ABC-123"
        product.supplierName = nil

        #expect(product.supplier == nil)
    }

    @Test("R-02-1: the customer side of a sale behaves identically")
    func test_R0201_saleCustomerRoundTrips() {
        let sale = Sale(number: "20260821-001", totalRp: 29000)

        #expect(sale.customer == nil)

        sale.customer = Self.budi
        #expect(sale.customerContactID == "ABC-123")
        #expect(sale.customerName == "Budi Santoso")

        sale.customer = nil
        #expect(sale.customerContactID == nil)
        #expect(sale.customerName == nil)
    }
}

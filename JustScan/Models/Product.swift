//
//  Product.swift
//  JustScan
//
//  Storage only. Every rule, validation, and mutation belongs to module 03,
//  which owns this entity. Declared here because the Schema in
//  PersistenceController cannot exist without it (01 §5).
//  Fields are verbatim from 03 §5.
//

import Foundation
import SwiftData

@Model final class Product {
    var id: UUID = UUID()
    var name: String = ""
    var priceRp: Int = 0

    /// Cached sum of `movements` deltas. Written **only** by `StockService` (R-03-6).
    var stockQty: Int = 0

    /// Unique among non-deleted products, enforced in `ProductRepository` (R-03-1, ADR-02).
    /// Never `@Attribute(.unique)` — CloudKit does not support unique constraints.
    var barcode: String?

    var supplierContactID: String?
    var supplierName: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Soft delete (R-03-12). Never `modelContext.delete()`.
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StockMovement.product)
    var movements: [StockMovement]? = []

    /// R-02-1 and R-02-5: the two supplier columns are read and written as one
    /// value, so an ID without a name — or a name without an ID — is not a state
    /// this model can be left in. Owned by module 02; the columns above are
    /// still plain storage.
    var supplier: ContactRef? {
        get { ContactRef.paired(id: supplierContactID, name: supplierName) }
        set {
            supplierContactID = newValue?.id
            supplierName = newValue?.name
        }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        priceRp: Int = 0,
        stockQty: Int = 0,
        barcode: String? = nil,
        supplierContactID: String? = nil,
        supplierName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.priceRp = priceRp
        self.stockQty = stockQty
        self.barcode = barcode
        self.supplierContactID = supplierContactID
        self.supplierName = supplierName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.movements = []
    }
}

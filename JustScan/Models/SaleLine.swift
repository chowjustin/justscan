//
//  SaleLine.swift
//  JustScan
//
//  Storage only. Owned by module 04. Fields verbatim from 04 §5.
//

import Foundation
import SwiftData

@Model final class SaleLine {
    var id: UUID = UUID()

    var sale: Sale?

    /// Deliberately a weak `UUID?` and **not** a SwiftData relationship (D-15).
    /// A product deletion must be structurally incapable of touching financial history.
    var productID: UUID?

    /// Snapshotted at tender. Later catalogue edits never alter a completed sale (R-04-3).
    var nameSnapshot: String = ""
    var unitPriceRp: Int = 0

    var qty: Int = 1

    /// Stored, = `unitPriceRp × qty` (R-04-5).
    var lineTotalRp: Int = 0

    init(
        id: UUID = UUID(),
        sale: Sale? = nil,
        productID: UUID? = nil,
        nameSnapshot: String = "",
        unitPriceRp: Int = 0,
        qty: Int = 1,
        lineTotalRp: Int = 0
    ) {
        self.id = id
        self.sale = sale
        self.productID = productID
        self.nameSnapshot = nameSnapshot
        self.unitPriceRp = unitPriceRp
        self.qty = qty
        self.lineTotalRp = lineTotalRp
    }
}

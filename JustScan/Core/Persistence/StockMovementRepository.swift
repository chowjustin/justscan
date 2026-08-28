//
//  StockMovementRepository.swift
//  JustScan
//
//  Append-only. A movement is never updated and never deleted (R-03-10);
//  a wrong movement is corrected by an offsetting `.adjustment`.
//
//  There is deliberately no `save()` here — see ProductRepository.save().
//

import Foundation
import SwiftData

protocol StockMovementRepository {
    /// Every movement for this product, newest first.
    func movements(for product: Product) throws -> [StockMovement]

    /// Stage an insert. Committed by `ProductRepository.save()`, in the same
    /// transaction as the `stockQty` cache update (R-03-11).
    func insert(_ movement: StockMovement)
}

struct SwiftDataStockMovementRepository: StockMovementRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func movements(for product: Product) throws -> [StockMovement] {
        let productID = product.id
        let descriptor = FetchDescriptor<StockMovement>(
            // No ordered relationships (foundations §6) — sort explicitly.
            sortBy: [SortDescriptor(\StockMovement.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
            .filter { $0.product?.id == productID }
    }

    func insert(_ movement: StockMovement) {
        context.insert(movement)
    }
}

//
//  InMemoryStockMovementRepository.swift
//  JustScanTests
//
//  The ledger half of the failure-path fake. Pairs with
//  `InMemoryProductRepository`, which owns `save()`.
//

import Foundation
@testable import JustScan

final class InMemoryStockMovementRepository: StockMovementRepository, @unchecked Sendable {
    private(set) var stored: [StockMovement] = []

    func movements(for product: Product) throws -> [StockMovement] {
        let productID = product.id
        return stored
            .filter { $0.product?.id == productID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func insert(_ movement: StockMovement) {
        stored.append(movement)
    }
}

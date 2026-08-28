//
//  Sale.swift
//  JustScan
//
//  Storage only. Owned by module 04. Fields verbatim from 04 §5.
//

import Foundation
import SwiftData

/// One per sale (D-07).
enum PaymentMethod: String, CaseIterable, Sendable {
    case cash
    case qris
}

/// `completed → voided` is the only transition, and it is terminal (04 §6).
enum SaleStatus: String, CaseIterable, Sendable {
    case completed
    case voided
}

@Model final class Sale {
    var id: UUID = UUID()

    /// `{YYYYMMDD}-{NNN}` in Asia/Jakarta (R-04-4). Retained through a void.
    var number: String = ""

    /// Stored sum of line totals, not computed at read time (R-04-5).
    var totalRp: Int = 0

    var paymentMethodRaw: String = PaymentMethod.cash.rawValue

    /// Cash only. `nil` for QRIS — nil means "not applicable", never 0 (R-04-10).
    var cashReceivedRp: Int?
    var changeRp: Int?

    var customerContactID: String?
    var customerName: String?

    var statusRaw: String = SaleStatus.completed.rawValue
    var voidedAt: Date?
    var voidReason: String?

    /// Tender time.
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SaleLine.sale)
    var lines: [SaleLine]? = []

    /// Typed accessors with explicit unknown-value fallbacks (foundations §6).
    var method: PaymentMethod {
        PaymentMethod(rawValue: paymentMethodRaw) ?? .cash
    }

    var status: SaleStatus {
        SaleStatus(rawValue: statusRaw) ?? .completed
    }

    init(
        id: UUID = UUID(),
        number: String = "",
        totalRp: Int = 0,
        method: PaymentMethod = .cash,
        cashReceivedRp: Int? = nil,
        changeRp: Int? = nil,
        customerContactID: String? = nil,
        customerName: String? = nil,
        status: SaleStatus = .completed,
        voidedAt: Date? = nil,
        voidReason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.number = number
        self.totalRp = totalRp
        self.paymentMethodRaw = method.rawValue
        self.cashReceivedRp = cashReceivedRp
        self.changeRp = changeRp
        self.customerContactID = customerContactID
        self.customerName = customerName
        self.statusRaw = status.rawValue
        self.voidedAt = voidedAt
        self.voidReason = voidReason
        self.createdAt = createdAt
        self.lines = []
    }
}

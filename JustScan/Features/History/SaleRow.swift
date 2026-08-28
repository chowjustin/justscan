//
//  SaleRow.swift
//  JustScan
//
//  One history line: `number · HH:mm · payment icon · totalRp` (05 §10).
//
//  A voided sale is struck through and dropped to the secondary colour. It is
//  never removed — it is in no total, and it is always still listed (R-05-2).
//
//  Times are `HH:mm` in Asia/Jakarta, always. The device's own zone is exactly
//  what `JakartaDay` exists to ignore (R-05-1).
//

import SwiftUI

struct SaleRow: View {
    let sale: Sale

    private var isVoided: Bool { sale.status == .voided }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sale.number)
                    .monospacedDigit()
                    .strikethrough(isVoided)
                Text(JakartaDay.time(sale.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: sale.method.icon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(Rp.format(sale.totalRp))
                .font(.headline)
                .monospacedDigit()
                .strikethrough(isVoided)
        }
        .foregroundStyle(isVoided ? Color.secondary : Color.primary)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let base = "\(sale.number), \(JakartaDay.time(sale.createdAt)), "
            + "\(sale.method.label), \(Rp.format(sale.totalRp))"
        return isVoided ? base + ", dibatalkan" : base
    }
}

/// Operator-facing labels and the two icons of 05 §10. Display only — nothing
/// decides anything from these, and `PaymentMethod`'s raw values stay English.
extension PaymentMethod {
    var label: String {
        switch self {
        case .cash: return "Tunai"
        case .qris: return "QRIS"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .qris: return "qrcode"
        }
    }
}

#if DEBUG
#Preview {
    List {
        SaleRow(sale: Sale(number: "20260821-001", totalRp: 29_000, method: .cash,
                           cashReceivedRp: 50_000, changeRp: 21_000))
        SaleRow(sale: Sale(number: "20260821-002", totalRp: 12_000, method: .qris))
        SaleRow(sale: Sale(number: "20260821-003", totalRp: 8_000, method: .cash,
                           status: .voided, voidedAt: Date(), voidReason: "salah barang"))
    }
}
#endif

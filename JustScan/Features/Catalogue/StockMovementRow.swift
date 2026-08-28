//
//  StockMovementRow.swift
//  JustScan
//
//  One ledger line: `±delta · reason · date`, sign-coloured (03 §10).
//  Dates are `d MMM, HH:mm` in Asia/Jakarta, always — the device's own timezone
//  is exactly what `JakartaDay` exists to ignore.
//

import SwiftUI

struct StockMovementRow: View {
    let movement: StockMovement

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(signed)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(movement.delta < 0 ? Color.red : Color.green)
                .frame(minWidth: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(movement.reason.label)
                if let note = movement.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(JakartaDay.shortDateTime(movement.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var signed: String {
        movement.delta > 0 ? "+\(movement.delta)" : "\(movement.delta)"
    }
}

/// Operator-facing labels, Indonesian. Display only — nothing decides anything
/// from these strings, and `StockReason`'s raw values stay English (R-03-13).
extension StockReason {
    var label: String {
        switch self {
        case .opening:    return "Stok awal"
        case .restock:    return "Tambah stok"
        case .sale:       return "Penjualan"
        case .void:       return "Pembatalan"
        case .adjustment: return "Koreksi"
        }
    }
}

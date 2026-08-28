//
//  CartLineRow.swift
//  JustScan
//
//  One cart line: name, `qty × unitPrice`, and the line total right-aligned
//  (04 §10). Money renders through `Rp.format` and nowhere else.
//

import SwiftUI

struct CartLineRow: View {
    let line: DraftLine
    let isOutOfStock: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.name)

                HStack(spacing: 6) {
                    Text("\(line.qty) × \(Rp.format(line.unitPriceRp))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if isOutOfStock {
                        OutOfStockChip()
                    }
                }
            }

            Spacer(minLength: 12)

            Text(Rp.format(line.lineTotalRp))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A warning, never a block. The sale always proceeds (R-04-6, D-05).
private struct OutOfStockChip: View {
    var body: some View {
        Text("Stok habis")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
    }
}

#if DEBUG
#Preview {
    List {
        CartLineRow(
            line: DraftLine(productID: UUID(), name: "Chitato Sapi Panggang 68g",
                            unitPriceRp: 12_000, qty: 2),
            isOutOfStock: false
        )
        CartLineRow(
            line: DraftLine(productID: UUID(), name: "Teh Botol Sosro 350ml",
                            unitPriceRp: 5_000, qty: 3),
            isOutOfStock: true
        )
    }
}
#endif

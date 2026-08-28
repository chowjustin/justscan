//
//  PaymentSuccessView.swift
//  JustScan
//
//  Change due, in the largest type the screen allows, or "Lunas — QRIS"
//  (04 §10). Auto-dismisses after three seconds, or on tap.
//
//  The cart is already empty by the time this appears — the reset happens at
//  commit, not at dismissal, so the screen behind is ready for the next
//  customer immediately (AC-04-18).
//

import SwiftUI

struct PaymentSuccessView: View {
    let sale: Sale
    let onDismiss: () -> Void

    /// 04 §3.6.
    private static let autoDismissAfter = Duration.seconds(3)

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            if let changeRp = sale.changeRp {
                VStack(spacing: 6) {
                    Text("Kembalian")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(Rp.format(changeRp))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            } else {
                // R-04-10: nil is "not applicable", so there is no amount to
                // show — not a zero.
                Text("Lunas — QRIS")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            Text(sale.number)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text("Ketuk untuk menutup")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .task {
            try? await Task.sleep(for: Self.autoDismissAfter)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(
            sale.changeRp.map { "Kembalian \(Rp.format($0))" } ?? "Lunas, QRIS"
        )
    }
}

#if DEBUG
#Preview("Tunai") {
    PaymentSuccessView(
        sale: Sale(number: "20260821-001", totalRp: 29_000, method: .cash,
                   cashReceivedRp: 50_000, changeRp: 21_000),
        onDismiss: {}
    )
}

#Preview("QRIS") {
    PaymentSuccessView(
        sale: Sale(number: "20260821-002", totalRp: 29_000, method: .qris),
        onDismiss: {}
    )
}
#endif

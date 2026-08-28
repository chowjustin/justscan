//
//  TenderSheet.swift
//  JustScan
//
//  Total, `Tunai | QRIS`, cash entry with quick-pick chips, confirm (04 §10).
//  The one modal permitted to block scanning, and the only one.
//
//  Every number on this sheet comes from `TenderViewModel`; the view does no
//  arithmetic and formats money only through `Rp.format`.
//

import SwiftUI

struct TenderSheet: View {
    let totalRp: Int
    /// Committed by the caller — a sheet does not call a service.
    let onConfirm: (PaymentMethod, Int?) -> Void

    @State private var model: TenderViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCashFocused: Bool

    init(totalRp: Int, onConfirm: @escaping (PaymentMethod, Int?) -> Void) {
        self.totalRp = totalRp
        self.onConfirm = onConfirm
        _model = State(initialValue: TenderViewModel(totalRp: totalRp))
    }

    var body: some View {
        NavigationStack {
            Form {
                totalSection
                methodSection
                if model.method == .cash {
                    cashSection
                    quickPickSection
                } else {
                    qrisSection
                }
            }
            .navigationTitle("Bayar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Never a modal the operator can be trapped in
                // (CONVENTIONS.md).
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Konfirmasi") {
                        onConfirm(model.method, model.cashReceivedRp)
                        dismiss()
                    }
                    .disabled(!model.canConfirm)
                }
            }
        }
    }

    private var totalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Rp.format(totalRp))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var methodSection: some View {
        Section {
            Picker("Metode", selection: $model.method) {
                Text("Tunai").tag(PaymentMethod.cash)
                Text("QRIS").tag(PaymentMethod.qris)
            }
            .pickerStyle(.segmented)
        }
    }

    private var cashSection: some View {
        Section {
            TextField("Uang diterima", text: $model.cashText)
                .keyboardType(.numberPad)
                .font(.title2)
                .monospacedDigit()
                .focused($isCashFocused)

            if let shortfallRp = model.shortfallRp {
                // 04 §11: "Kurang Rp 4.000".
                Label("Kurang \(Rp.format(shortfallRp))", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if let changeRp = model.changeRp {
                LabeledContent("Kembalian") {
                    Text(Rp.format(changeRp))
                        .font(.headline)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Uang diterima")
        }
    }

    private var quickPickSection: some View {
        Section {
            // A flexible grid rather than a row: the chips must stay tappable
            // at XL Dynamic Type, which 04 §10 requires of this screen.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                Button("Pas") { model.selectExactAmount() }
                    .buttonStyle(.bordered)

                ForEach(model.quickPicks, id: \.self) { amount in
                    Button(Rp.format(amount)) { model.select(amountRp: amount) }
                        .buttonStyle(.bordered)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Pilih cepat")
        }
    }

    private var qrisSection: some View {
        Section {
            // No amount entry: QRIS is exact by construction, and confirming
            // means "I saw the payment succeed on the customer's phone"
            // (04 §3, D-08).
            Label("Pelanggan membayar lewat QRIS di meja kasir.",
                  systemImage: "qrcode")
            Text("Konfirmasi berarti pembayaran sudah terlihat berhasil.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    TenderSheet(totalRp: 29_000) { _, _ in }
}
#endif

//
//  VoidSheet.swift
//  JustScan
//
//  Sale summary, a required reason, and a destructive confirm (04 §10).
//
//  Presented from module 05's sale detail screen (04 §3). It ships here because
//  the void belongs to this module: 05 presents it and implements none of it.
//  Until 05 exists this sheet has no call site in the app, which is expected.
//
//  Note what is absent: an approval step. There is nobody to approve it
//  (04 §2, foundations §3), and that is the sharpest edge of the no-roles
//  decision.
//

import SwiftUI

struct VoidSheet: View {
    let sale: Sale
    /// Committed by the caller — a sheet does not call a service.
    let onConfirm: (String) -> Void

    /// R-04-14.
    private static let reasonLimit = 120

    @State private var reason: String = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        (1...Self.reasonLimit).contains(trimmedReason.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Nomor", value: sale.number)
                    LabeledContent("Total") {
                        Text(Rp.format(sale.totalRp)).monospacedDigit()
                    }
                    LabeledContent("Waktu", value: JakartaDay.shortDateTime(sale.createdAt))
                }

                Section {
                    TextField("Alasan pembatalan", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Alasan")
                } footer: {
                    // A void with no reason is a void nobody can explain later
                    // (R-04-14).
                    Text("Wajib diisi, maksimal \(Self.reasonLimit) karakter. \(trimmedReason.count)/\(Self.reasonLimit)")
                }

                Section {
                    Text("Stok akan dikembalikan dan transaksi tidak dihitung lagi. Nomor transaksi tetap disimpan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Batalkan Transaksi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Batalkan", role: .destructive) {
                        onConfirm(trimmedReason)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    VoidSheet(
        sale: Sale(number: "20260821-001", totalRp: 29_000, method: .cash,
                   cashReceivedRp: 50_000, changeRp: 21_000),
        onConfirm: { _ in }
    )
}
#endif

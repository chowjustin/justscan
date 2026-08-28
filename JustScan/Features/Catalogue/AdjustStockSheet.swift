//
//  AdjustStockSheet.swift
//  JustScan
//
//  "Koreksi Stok" — the operator enters the **actual counted quantity**, not a
//  delta (03 §3). Asking for a delta asks them to do arithmetic while standing
//  at a shelf; the service does it instead.
//
//  Counting the same number twice writes nothing: recording a no-op pollutes a
//  ledger whose whole job is to explain a quantity.
//

import SwiftUI

struct AdjustStockSheet: View {
    let productName: String
    let currentQty: Int
    let onConfirm: (Int, String) -> Void

    @State private var countedQty: Int
    @State private var reason: Reason = .expired
    @Environment(\.dismiss) private var dismiss

    /// The three reasons of 03 §3. The chosen label becomes the movement's
    /// `note`, which is what makes a ledger row readable a month later.
    enum Reason: String, CaseIterable, Identifiable {
        case expired = "Kedaluwarsa"
        case lost = "Hilang"
        case miscount = "Salah hitung"

        var id: String { rawValue }
    }

    init(productName: String, currentQty: Int, onConfirm: @escaping (Int, String) -> Void) {
        self.productName = productName
        self.currentQty = currentQty
        self.onConfirm = onConfirm
        _countedQty = State(initialValue: max(0, currentQty))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Jumlah dihitung", value: $countedQty, format: .number)
                        .keyboardType(.numberPad)
                        .font(.largeTitle)
                        .monospacedDigit()
                } header: {
                    Text("Jumlah sebenarnya di rak")
                } footer: {
                    Text("\(productName) · tercatat \(currentQty)")
                }

                Section("Alasan") {
                    Picker("Alasan", selection: $reason) {
                        ForEach(Reason.allCases) { reason in
                            Text(reason.rawValue).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if countedQty == currentQty {
                    Section {
                        Text("Jumlah sama dengan catatan. Tidak ada yang dicatat.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Koreksi Stok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        onConfirm(countedQty, reason.rawValue)
                        dismiss()
                    }
                    .disabled(countedQty < 0)
                }
            }
        }
    }
}

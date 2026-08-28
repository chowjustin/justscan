//
//  AddStockSheet.swift
//  JustScan
//
//  "Tambah Stok" — a number pad, default 1 (03 §3). Goods arrived, so this is
//  always a `.restock`; correcting a count is `AdjustStockSheet`, which is a
//  different question with a different answer.
//

import SwiftUI

struct AddStockSheet: View {
    let productName: String
    let onConfirm: (Int) -> Void

    @State private var qty: Int = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Jumlah", value: $qty, format: .number)
                        .keyboardType(.numberPad)
                        .font(.largeTitle)
                        .monospacedDigit()
                } header: {
                    Text("Jumlah masuk")
                } footer: {
                    Text(productName)
                }

                Section {
                    Stepper("Jumlah: \(qty)", value: $qty, in: 1...9_999)
                }
            }
            .navigationTitle("Tambah Stok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Never a modal the operator can be trapped in (CONVENTIONS.md).
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        onConfirm(qty)
                        dismiss()
                    }
                    .disabled(qty < 1)
                }
            }
        }
    }
}

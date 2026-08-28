//
//  ProductFormView.swift
//  JustScan
//
//  New and edit, one view (03 §10). Barcode shown and locked, name, price on a
//  number pad formatted live in `id_ID`, supplier through module 02's shared
//  `ContactField`.
//
//  The R-03-8 warning is a yellow inline banner above the fields — never a
//  blocking alert. The operator is allowed to be right about their own shop.
//

import SwiftUI

struct ProductFormView: View {
    @State private var model: ProductFormViewModel
    private let onSaved: (Product) -> Void
    private let onShowExisting: (Product) -> Void

    init(mode: ProductFormViewModel.Mode,
         container: AppContainer,
         onSaved: @escaping (Product) -> Void,
         onShowExisting: @escaping (Product) -> Void) {
        self.onSaved = onSaved
        self.onShowExisting = onShowExisting
        _model = State(
            initialValue: ProductFormViewModel(mode: mode,
                                               catalogue: container.catalogue,
                                               contacts: container.contacts)
        )
    }

    var body: some View {
        Form {
            if let warning = model.internalCodeWarning {
                Section {
                    InternalCodeBanner(message: warning)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Barcode") {
                LabeledContent("Barcode") {
                    Text(model.barcodeLabel)
                        .foregroundStyle(model.barcode == nil ? .secondary : .primary)
                        .monospacedDigit()
                }
            }

            Section("Detail") {
                TextField("Nama produk", text: $model.name)
                    .textInputAutocapitalization(.words)

                LabeledContent("Harga") {
                    TextField("Rp 0", text: priceText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }

                ContactField(label: "Supplier", viewModel: model.supplierField)
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Simpan") {
                    if let saved = model.save() { onSaved(saved) }
                }
                .disabled(!model.canSave)
            }
        }
        .alert(
            "Tidak bisa menyimpan",
            isPresented: Binding(get: { model.errorMessage != nil },
                                 set: { if !$0 { model.dismissError() } })
        ) {
            // §11: the operator can go straight to the product holding the code.
            if let existing = model.conflicting {
                Button("Lihat") {
                    model.dismissError()
                    onShowExisting(existing)
                }
            }
            Button("Tutup", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Live `id_ID` formatting over an `Int` (03 §10). No `Decimal`, no
    /// `Double` — the digits the operator types are the rupiah, exactly.
    private var priceText: Binding<String> {
        Binding(
            get: { model.priceRp == 0 ? "" : Rp.format(model.priceRp) },
            set: { typed in
                let digits = typed.filter { $0.isASCIIDigit }
                model.priceRp = Int(digits.prefix(12)) ?? 0
            }
        )
    }
}

/// R-03-8. Yellow, inline, above the fields, and dismissable only by acting on
/// it — the operator may proceed regardless.
private struct InternalCodeBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

private extension Character {
    /// Matches `BarcodeKind`'s deliberate ASCII-only stance: a number pad emits
    /// ASCII digits, and accepting other digit forms would only widen the gap
    /// between what is typed and what is stored.
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}

//
//  ProductDetailView.swift
//  JustScan
//
//  Name, price, supplier, current stock in large type, and the ledger that
//  explains it — newest first (03 §10).
//
//  Every action here routes through a service. This view never assigns
//  `stockQty` and never touches a `ModelContext`.
//

import SwiftUI

struct ProductDetailView: View {
    @State private var model: ProductDetailViewModel
    @Binding private var path: [ProductListViewModel.Route]

    @State private var isAddingStock = false
    @State private var isAdjusting = false
    @State private var isConfirmingDelete = false

    init(product: Product,
         container: AppContainer,
         path: Binding<[ProductListViewModel.Route]>) {
        _path = path
        _model = State(
            initialValue: ProductDetailViewModel(product: product,
                                                 catalogue: container.catalogue,
                                                 stock: container.stock,
                                                 contacts: container.contacts)
        )
    }

    var body: some View {
        List {
            stockSection
            detailSection
            actionsSection
            ledgerSection
        }
        .navigationTitle(model.product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
        .onAppear { model.load() }
        .onChange(of: model.supplierField.ref) { model.saveSupplier() }
        .onChange(of: model.isDeleted) { if model.isDeleted { path.removeLast() } }
        .sheet(isPresented: $isAddingStock) {
            AddStockSheet(productName: model.product.name) { model.addStock($0) }
        }
        .sheet(isPresented: $isAdjusting) {
            AdjustStockSheet(productName: model.product.name,
                             currentQty: model.product.stockQty) { counted, note in
                model.adjust(countedQty: counted, note: note)
            }
        }
        .confirmationDialog("Hapus produk ini?",
                            isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            Button("Hapus", role: .destructive) { model.delete() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Produk hilang dari katalog dan dari hasil scan. Riwayat penjualan tidak berubah.")
        }
        .alert("Hitung Ulang", isPresented: Binding(
            get: { model.recomputeResult != nil },
            set: { if !$0 { model.dismissRecomputeResult() } })
        ) {
            Button("Tutup", role: .cancel) { model.dismissRecomputeResult() }
        } message: {
            Text(recomputeMessage)
        }
        .alert("Terjadi kesalahan", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } })
        ) {
            Button("Tutup", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var stockSection: some View {
        Section {
            VStack(spacing: 4) {
                Text("\(model.product.stockQty)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.product.stockQty <= 0 ? Color.red : Color.primary)
                    .minimumScaleFactor(0.5)
                Text("Stok saat ini")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private var detailSection: some View {
        Section("Detail") {
            LabeledContent("Harga", value: Rp.format(model.product.priceRp))
            LabeledContent("Barcode") {
                Text(model.product.barcode ?? "Tanpa barcode")
                    .foregroundStyle(model.product.barcode == nil ? .secondary : .primary)
                    .monospacedDigit()
            }
            ContactField(label: "Supplier", viewModel: model.supplierField)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                isAddingStock = true
            } label: {
                Label("Tambah Stok", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)

            Button {
                isAdjusting = true
            } label: {
                Label("Koreksi Stok", systemImage: "slider.horizontal.3")
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var ledgerSection: some View {
        Section("Riwayat Stok") {
            if model.movements.isEmpty {
                // Zero stock is the absence of movements, never a movement of
                // zero (R-03-13) — so an empty ledger is a normal state, not an
                // error.
                Text("Belum ada pergerakan stok.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.movements) { movement in
                    StockMovementRow(movement: movement)
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button {
                path.append(.edit(model.product))
            } label: {
                Label("Ubah", systemImage: "pencil")
            }

            Button {
                model.recompute()
            } label: {
                Label("Hitung Ulang dari Riwayat", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Hapus", systemImage: "trash")
            }
        } label: {
            Label("Menu", systemImage: "ellipsis.circle")
        }
    }

    /// A difference is a cache bug, so it is stated plainly rather than
    /// smoothed over (03 §3).
    private var recomputeMessage: String {
        guard let result = model.recomputeResult else { return "" }
        return result.matches
            ? "Stok cocok: \(result.after)."
            : "Stok tercatat \(result.before), hasil hitung ulang \(result.after). "
            + "Angka sudah diperbaiki."
    }
}

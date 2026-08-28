//
//  CartView.swift
//  JustScan
//
//  The Jual tab — the app's home screen, and the one that never navigates away
//  from itself during a normal sale (04 §1, §10).
//
//  Layout is fixed and vertical: lines at the top with the newest first, and a
//  bottom bar carrying the total in the largest type on the screen plus the two
//  buttons that matter. Both sit in the bottom third, reachable one-handed at a
//  counter.
//
//  No SwiftData, no @Query, no arithmetic. Money renders through `Rp.format`.
//

import SwiftUI

struct CartView: View {
    private let container: AppContainer
    @State private var model: CartViewModel
    @State private var path: [CartViewModel.Route] = []
    @State private var isScanning = false
    @State private var isTendering = false
    @State private var isConfirmingDiscard = false
    @State private var editingLine: DraftLine?
    @State private var lastScan: CartViewModel.ScanOutcome?
    @State private var tenderCount = 0

    init(container: AppContainer) {
        self.container = container
        _model = State(
            initialValue: CartViewModel(catalogue: container.catalogue,
                                        sales: container.sales,
                                        scanner: container.scanner,
                                        contacts: container.contacts)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if let code = model.unknownBarcode {
                    UnknownBarcodeBanner(
                        barcode: code,
                        willDiscardCart: !model.isEmpty,
                        onAdd: addProductForUnknownBarcode,
                        onDismiss: model.dismissUnknownBarcode
                    )
                }

                cart
                bottomBar
            }
            .navigationTitle("Jual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: CartViewModel.Route.self, destination: destination)
            .sheet(item: $editingLine) { line in
                LineQuantitySheet(line: line) { model.setQty($0, for: line.productID) }
            }
            .sheet(isPresented: $isTendering) {
                // 04 §10: the only modal permitted to block scanning.
                TenderSheet(totalRp: model.totalRp) { method, cashReceivedRp in
                    if model.tender(method: method, cashReceivedRp: cashReceivedRp) {
                        tenderCount += 1
                    }
                }
            }
            .fullScreenCover(item: successBinding) { sale in
                PaymentSuccessView(sale: sale, onDismiss: model.dismissSuccess)
            }
            .confirmationDialog("Buang keranjang?", isPresented: $isConfirmingDiscard,
                                titleVisibility: .visible) {
                Button("Buang", role: .destructive) { model.discard() }
                Button("Batal", role: .cancel) { }
            } message: {
                Text("Semua barang di keranjang akan dihapus.")
            }
            .alert(
                "Tidak bisa melanjutkan",
                isPresented: Binding(get: { model.errorMessage != nil },
                                     set: { if !$0 { model.dismissError() } })
            ) {
                Button("Tutup", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
            // 04 §10: success on line add and on tender complete, warning on an
            // unknown barcode.
            .sensoryFeedback(.success, trigger: model.lines.count)
            .sensoryFeedback(.success, trigger: tenderCount)
            .sensoryFeedback(.warning, trigger: model.unknownBarcode)
        }
    }

    // MARK: - Cart

    @ViewBuilder
    private var cart: some View {
        if model.isEmpty {
            ContentUnavailableView {
                Label("Keranjang kosong", systemImage: "cart")
            } description: {
                Text("Scan barang untuk mulai.")
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(model.lines, id: \.productID) { line in
                        Button {
                            editingLine = line
                        } label: {
                            CartLineRow(line: line,
                                        isOutOfStock: model.isOutOfStock(productID: line.productID))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Hapus", role: .destructive) {
                                model.remove(productID: line.productID)
                            }
                        }
                    }
                }

                Section {
                    // Module 02's shared row, embedded as "Pelanggan"
                    // (04 §3.9). Optional, always.
                    ContactField(label: "Pelanggan", viewModel: model.customerField)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Rp.format(model.totalRp))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .monospacedDigit()
                    .accessibilityLabel("Total \(Rp.format(model.totalRp))")
            }

            Button(action: scan) {
                Label("Scan", systemImage: "barcode.viewfinder")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)

            Button {
                isTendering = true
            } label: {
                Text("Bayar")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            // R-04-7's guard lives in the service; this is the courtesy.
            .disabled(!model.canTender)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Buang", role: .destructive) { isConfirmingDiscard = true }
                // Only offered when there is something to discard (04 §3.8).
                .disabled(model.isEmpty)
        }
    }

    // MARK: - Actions

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            defer { isScanning = false }
            lastScan = await model.scan()
        }
    }

    private func addProductForUnknownBarcode() {
        guard let route = model.addProductForUnknownBarcode() else { return }
        path.append(route)
    }

    /// `Sale` is a reference type without `Identifiable` conformance in the
    /// model layer, so the cover is driven by a small wrapper rather than by
    /// adding presentation concerns to a `@Model`.
    private var successBinding: Binding<CompletedSale?> {
        Binding(
            get: { model.completedSale.map(CompletedSale.init) },
            set: { if $0 == nil { model.dismissSuccess() } }
        )
    }

    @ViewBuilder
    private func destination(for route: CartViewModel.Route) -> some View {
        switch route {
        case .newProduct(let barcode):
            // 04 §8: the cart is already discarded by the time we get here, and
            // the banner said so. Saving returns to the empty cart, ready to
            // scan the product that was just created.
            ProductFormView(
                mode: .create(barcode: barcode),
                container: container,
                onSaved: { _ in path.removeAll() },
                onShowExisting: { _ in path.removeAll() }
            )
        }
    }
}

/// Identity for the success cover.
private struct CompletedSale: Identifiable {
    let sale: Sale
    var id: UUID { sale.id }

    init(_ sale: Sale) { self.sale = sale }
}

private extension View {
    func fullScreenCover(
        item: Binding<CompletedSale?>,
        @ViewBuilder content: @escaping (Sale) -> some View
    ) -> some View {
        fullScreenCover(item: item) { wrapper in content(wrapper.sale) }
    }
}

/// 04 §3.5. An inline banner, never a dialog: the cart is untouched and the
/// operator can keep scanning.
private struct UnknownBarcodeBanner: View {
    let barcode: String
    let willDiscardCart: Bool
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Produk tidak dikenal")
                    .font(.subheadline.weight(.semibold))
                Text(barcode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button("Tambah Produk Baru", action: onAdd)
                    .font(.subheadline.weight(.semibold))

                if willDiscardCart {
                    // 04 §8 requires the banner to say this out loud.
                    Text("Keranjang akan dikosongkan kalau kamu menambah produk sekarang.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tutup pemberitahuan")
        }
        .padding()
        .background(Color.orange.opacity(0.12))
    }
}

/// 04 §10: tapping a line opens a quantity stepper. Setting it to zero removes
/// the line (R-04-16), which the sheet says plainly.
private struct LineQuantitySheet: View {
    let line: DraftLine
    let onConfirm: (Int) -> Void

    @State private var qty: Int
    @Environment(\.dismiss) private var dismiss

    init(line: DraftLine, onConfirm: @escaping (Int) -> Void) {
        self.line = line
        self.onConfirm = onConfirm
        _qty = State(initialValue: line.qty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Jumlah: \(qty)", value: $qty, in: 0...9_999)
                        .monospacedDigit()
                } header: {
                    Text(line.name)
                } footer: {
                    Text(qty < 1
                         ? "Jumlah 0 akan menghapus barang ini dari keranjang."
                         : "Subtotal \(Rp.format(line.unitPriceRp * qty))")
                }
            }
            .navigationTitle("Ubah Jumlah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        onConfirm(qty)
                        dismiss()
                    }
                }
            }
        }
    }
}

extension DraftLine: Identifiable {
    var id: UUID { productID }
}

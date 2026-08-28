//
//  ProductListView.swift
//  JustScan
//
//  The Produk tab (03 §10). Name-ascending, deleted rows absent, and a large
//  Scan button that is the point of the whole app — the operator should reach
//  for it before they reach for the keyboard.
//
//  No SwiftData, no @Query, no money arithmetic. Money renders through
//  `Rp.format` alone.
//

import SwiftUI

struct ProductListView: View {
    private let container: AppContainer
    @State private var model: ProductListViewModel
    @State private var path: [ProductListViewModel.Route] = []
    @State private var isScanning = false

    init(container: AppContainer) {
        self.container = container
        _model = State(
            initialValue: ProductListViewModel(catalogue: container.catalogue,
                                               scanner: container.scanner)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Produk")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $model.query, prompt: "Cari produk")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        scanButton
                    }
                }
                .navigationDestination(for: ProductListViewModel.Route.self, destination: destination)
                .onChange(of: model.query) { model.load() }
                .onAppear { model.load() }
                .alert(
                    "Tidak bisa memindai",
                    isPresented: Binding(get: { model.errorMessage != nil },
                                         set: { if !$0 { model.dismissError() } })
                ) {
                    Button("Tutup", role: .cancel) { model.dismissError() }
                } message: {
                    Text(model.errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            ContentUnavailableView {
                Label("Belum ada produk", systemImage: "shippingbox")
            } description: {
                Text("Belum ada produk. Scan barcode untuk mulai.")
            } actions: {
                Button(action: scan) {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }
        } else if model.products.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            List(model.products) { product in
                NavigationLink(value: ProductListViewModel.Route.detail(product)) {
                    ProductRow(product: product)
                }
            }
            .listStyle(.plain)
        }
    }

    private var scanButton: some View {
        Button(action: scan) {
            Label("Scan", systemImage: "barcode.viewfinder")
                .font(.title3)
        }
        .disabled(isScanning)
        .accessibilityLabel("Scan barcode")
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            defer { isScanning = false }
            // A cancelled scan returns nil and changes nothing (03 §3.2).
            guard let route = await model.scan() else { return }
            path.append(route)
        }
    }

    @ViewBuilder
    private func destination(for route: ProductListViewModel.Route) -> some View {
        switch route {
        case .detail(let product):
            ProductDetailView(product: product, container: container, path: $path)

        case .newProduct(let barcode):
            ProductFormView(
                mode: .create(barcode: barcode),
                container: container,
                onSaved: { path = [.detail($0)] },
                onShowExisting: { path = [.detail($0)] }
            )

        case .edit(let product):
            ProductFormView(
                mode: .edit(product),
                container: container,
                onSaved: { _ in path.removeLast() },
                onShowExisting: { path = [.detail($0)] }
            )
        }
    }
}

/// One catalogue row: name, price, and the stock badge (03 §10).
private struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                Text(Rp.format(product.priceRp))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StockBadge(qty: product.stockQty)
        }
        .padding(.vertical, 2)
    }
}

/// Red at or below zero (03 §10). Negative is never clamped and never hidden —
/// it means goods left the shelf that the ledger did not know about (R-03-7).
struct StockBadge: View {
    let qty: Int

    var body: some View {
        Text("\(qty)")
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(qty <= 0 ? Color.red : Color.primary)
            .accessibilityLabel("Stok \(qty)")
    }
}

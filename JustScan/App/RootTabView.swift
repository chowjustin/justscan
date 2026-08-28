//
//  RootTabView.swift
//  JustScan
//
//  Three tabs, Jual selected on launch — the cashier screen is the app's home,
//  not the catalogue (01 §3).
//
//  Jual is module 04's `CartView` and Produk is module 03's `ProductListView`.
//  Riwayat is still a placeholder; module 05 replaces it.
//

import SwiftUI

struct RootTabView: View {
    /// Jual is the launch tab (01 §3, §10).
    @State private var selection: Tab = .jual

    /// Passed down rather than read again inside each screen: a screen builds
    /// its ViewModel in `init`, where the environment is not yet available.
    @Environment(AppContainer.self) private var container

    private enum Tab: Hashable {
        case jual, produk, riwayat
    }

    var body: some View {
        TabView(selection: $selection) {
            CartView(container: container)
                .tabItem { Label("Jual", systemImage: "cart") }
                .tag(Tab.jual)

            ProductListView(container: container)
                .tabItem { Label("Produk", systemImage: "shippingbox") }
                .tag(Tab.produk)

            PlaceholderScreen(
                title: "Riwayat",
                systemImage: "clock.arrow.circlepath",
                message: "Riwayat transaksi dibuat di modul 05."
            )
            .tabItem { Label("Riwayat", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.riwayat)
        }
    }
}

/// Native `ContentUnavailableView` inside a `NavigationStack`, so each tab
/// already has the title and empty-state treatment the real screens will use.
private struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}



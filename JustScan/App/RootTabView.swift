//
//  RootTabView.swift
//  JustScan
//
//  Three tabs, Jual selected on launch — the cashier screen is the app's home,
//  not the catalogue (01 §3).
//
//  The tab bodies are placeholders. Modules 03, 04, and 05 replace them with
//  their own screens; those screens live in Features/, created by the session
//  that owns them.
//

import SwiftUI

struct RootTabView: View {
    /// Jual is the launch tab (01 §3, §10).
    @State private var selection: Tab = .jual

    private enum Tab: Hashable {
        case jual, produk, riwayat
    }

    var body: some View {
        TabView(selection: $selection) {
            PlaceholderScreen(
                title: "Jual",
                systemImage: "cart",
                message: "Layar kasir dibuat di modul 04."
            )
            .tabItem { Label("Jual", systemImage: "cart") }
            .tag(Tab.jual)

            PlaceholderScreen(
                title: "Produk",
                systemImage: "shippingbox",
                message: "Katalog produk dibuat di modul 03."
            )
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

#Preview {
    RootTabView()
}

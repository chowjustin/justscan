//
//  RootTabView.swift
//  JustScan
//
//  Three tabs, Jual selected on launch — the cashier screen is the app's home,
//  not the catalogue (01 §3).
//
//  Jual is module 04's `CartView`, Produk module 03's `ProductListView`, and
//  Riwayat module 05's `HistoryView`. Every tab is real; nothing here is a
//  placeholder any more.
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

            HistoryView(container: container)
                .tabItem { Label("Riwayat", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.riwayat)
        }
    }
}



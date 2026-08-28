//
//  StoreUnavailableView.swift
//  JustScan
//
//  Shown only when the store itself will not load — the one condition under
//  which this app has nothing useful to offer (01 §8).
//
//  It deliberately offers no "reset" button. Recreating the store would delete
//  the operator's sales, and a lost day of takings is worse than a broken app.
//

import SwiftUI

struct StoreUnavailableView: View {
    let error: Error?

    var body: some View {
        ContentUnavailableView {
            Label("Data Tidak Bisa Dibuka", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Aplikasi tidak bisa membuka datanya. Tutup aplikasi lalu buka lagi. Kalau masih gagal, hubungi bantuan — jangan hapus aplikasi, datanya masih ada.")
        } actions: {
            if let error {
                // The underlying error is surfaced rather than hidden, so the
                // person helping has something to work with.
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
    }
}

#Preview {
    StoreUnavailableView(error: POSError.persistenceFailed("contoh"))
}

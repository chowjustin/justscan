//
//  SaleDetailView.swift
//  JustScan
//
//  What was sold, at the price it was sold for (05 §10). Every line renders
//  `nameSnapshot` and `unitPriceRp`; there is no live `Product` lookup on this
//  screen and no way to reach one (R-05-4).
//
//  **Batalkan** presents module 04's `VoidSheet`, which has shipped since
//  session 4 and is reused unchanged. This module owns none of the void: it
//  hands a reason to `SaleServicing.void` and refreshes the list behind it
//  without navigating away (05 §1, §3.3).
//

import SwiftUI

struct SaleDetailView: View {
    @State private var model: SaleDetailViewModel

    /// Lets the list behind this screen re-read after a void. The screen itself
    /// stays open and switches to its voided presentation (05 §8).
    private let onChanged: () -> Void

    @State private var isVoiding = false

    init(sale: Sale, container: AppContainer, onChanged: @escaping () -> Void) {
        self.onChanged = onChanged
        _model = State(initialValue: SaleDetailViewModel(sale: sale,
                                                          sales: container.sales))
    }

    var body: some View {
        List {
            if model.isVoided { voidBanner }
            headerSection
            linesSection
            paymentSection
            if let customer = model.customer { customerSection(customer) }
            if model.canVoid { voidSection }
        }
        .navigationTitle(model.sale.number)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isVoiding) {
            VoidSheet(sale: model.sale) { reason in model.void(reason: reason) }
        }
        .onChange(of: model.didVoid) { if model.didVoid { onChanged() } }
        .alert("Terjadi kesalahan", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } })
        ) {
            Button("Tutup", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    /// Destructive-tinted, with the reason and the time (05 §10). A voided sale
    /// gets this and no void action.
    private var voidBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label("Transaksi dibatalkan", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                if let voidedAt = model.sale.voidedAt {
                    Text(JakartaDay.fullDateTime(voidedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = model.sale.voidReason {
                    Text(reason)
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.red.opacity(0.12))
    }

    private var headerSection: some View {
        Section {
            LabeledContent("Nomor") {
                Text(model.sale.number).monospacedDigit()
            }
            LabeledContent("Waktu", value: JakartaDay.fullDateTime(model.sale.createdAt))
        }
    }

    private var linesSection: some View {
        Section("Barang") {
            ForEach(model.lines) { line in
                SaleLineRow(line: line)
            }

            LabeledContent("Total") {
                Text(Rp.format(model.sale.totalRp))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
    }

    private var paymentSection: some View {
        Section("Pembayaran") {
            LabeledContent("Metode") {
                Label(model.sale.method.label, systemImage: model.sale.method.icon)
            }

            // Cash only. For QRIS both figures are nil meaning "not applicable",
            // which is not the same as zero (R-04-10, D-08).
            if model.showsCashDetail {
                if let received = model.sale.cashReceivedRp {
                    LabeledContent("Uang diterima") {
                        Text(Rp.format(received)).monospacedDigit()
                    }
                }
                if let change = model.sale.changeRp {
                    LabeledContent("Kembalian") {
                        Text(Rp.format(change)).monospacedDigit()
                    }
                }
            }
        }
    }

    /// The name snapshot, never a re-resolve. A deleted contact still reads
    /// (D-11, R-02-2), and a read-only screen never raises a permission prompt.
    private func customerSection(_ customer: ContactRef) -> some View {
        Section("Pelanggan") {
            Label(customer.name, systemImage: "person.crop.circle")
        }
    }

    private var voidSection: some View {
        Section {
            Button(role: .destructive) {
                isVoiding = true
            } label: {
                Label("Batalkan", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text("Stok dikembalikan dan transaksi tidak dihitung lagi. Nomor transaksi tetap disimpan.")
        }
    }
}

/// `name · qty × unitPrice · lineTotal` (05 §10), all from the snapshot.
private struct SaleLineRow: View {
    let line: SaleLine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.nameSnapshot)
            HStack {
                Text("\(line.qty) × \(Rp.format(line.unitPriceRp))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(Rp.format(line.lineTotalRp))
                    .font(.subheadline)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

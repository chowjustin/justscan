//
//  HistoryView.swift
//  JustScan
//
//  The Riwayat tab (05 §10): a segmented control, a summary card, and the day's
//  sales newest first. Read-only — the one write it can reach is a void, two
//  screens away, and even that belongs to module 04.
//
//  No SwiftData, no @Query, no arithmetic. Money renders through `Rp.format`
//  and times through `JakartaDay`. Every figure on screen was derived by
//  `DaySummary` at read time (R-05-3).
//

import SwiftUI

struct HistoryView: View {
    private let container: AppContainer
    @State private var model: HistoryViewModel

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: HistoryViewModel(sales: container.sales))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scopePicker
                if model.showsSummaryCard {
                    DaySummaryCard(summary: model.summary)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
                content
            }
            .navigationTitle("Riwayat")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Sale.self) { sale in
                SaleDetailView(sale: sale,
                               container: container,
                               onChanged: { model.refresh() })
            }
            .onAppear { model.load() }
            .onChange(of: model.scope) { model.load() }
            .alert(
                "Terjadi kesalahan",
                isPresented: Binding(get: { model.errorMessage != nil },
                                     set: { if !$0 { model.dismissError() } })
            ) {
                Button("Tutup", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var scopePicker: some View {
        Picker("Rentang waktu", selection: $model.scope) {
            ForEach(HistoryViewModel.Scope.allCases, id: \.self) { scope in
                Text(scope.label).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            // R-05-7: an empty day is a normal state. The card above still
            // reads Rp 0 · 0 transaksi, so the screen is never blank.
            ContentUnavailableView {
                Label("Belum ada transaksi", systemImage: "clock.arrow.circlepath")
            } description: {
                Text(model.emptyMessage)
            }
        } else if model.isGrouped {
            groupedList
        } else {
            flatList
        }
    }

    private var flatList: some View {
        List(model.sales) { sale in
            NavigationLink(value: sale) { SaleRow(sale: sale) }
        }
        .listStyle(.plain)
    }

    private var groupedList: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.sales) { sale in
                        NavigationLink(value: sale) { SaleRow(sale: sale) }
                    }
                } header: {
                    DayHeader(group: group, showsSubtotal: model.showsSubtotal(for: group))
                }
            }

            if model.canLoadMore {
                // 05 §8: `Semua` appends on scroll. The read is local and
                // synchronous, so this row replaces itself immediately and
                // there is no spinner on a data path (foundations §8).
                Text("Memuat transaksi lama…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .onAppear { model.loadMore() }
            }
        }
        .listStyle(.plain)
    }
}

/// The summary card (05 §10). Total in the largest type on the screen, then the
/// count and the split, then the void note when there is one.
private struct DaySummaryCard: View {
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(JakartaDay.longDate(summary.day))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Rp.format(summary.totalRp))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("\(summary.saleCount) transaksi")
                .font(.subheadline)

            // Stays legible at XL Dynamic Type: the two figures wrap to their
            // own lines rather than truncating.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { split }
                VStack(alignment: .leading, spacing: 4) { split }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if summary.voidedCount > 0 {
                // R-05-2: context, never part of a total.
                Text("\(summary.voidedCount) dibatalkan")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var split: some View {
        Label("Tunai \(Rp.format(summary.cashRp))", systemImage: PaymentMethod.cash.icon)
        Label("QRIS \(Rp.format(summary.qrisRp))", systemImage: PaymentMethod.qris.icon)
    }
}

/// One `Semua` section header: the Jakarta day, and its subtotal once the day
/// is fully loaded (05 §10).
private struct DayHeader: View {
    let group: DaySummary.Group
    let showsSubtotal: Bool

    var body: some View {
        HStack {
            Text(JakartaDay.longDate(group.summary.day))
            Spacer()
            if showsSubtotal {
                Text(Rp.format(group.summary.totalRp))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

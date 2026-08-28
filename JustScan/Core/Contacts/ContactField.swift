//
//  ContactField.swift
//  JustScan
//
//  The one reusable row module 02 ships (02 §10). Catalogue embeds it as
//  "Supplier", Sale embeds it as "Pelanggan", and it is otherwise identical in
//  both — which is the reason this module is built before either of them.
//
//  No SwiftData, no @Query, no money arithmetic, and the Contacts framework
//  never appears here — the status crosses the boundary as `ContactAccess`,
//  which is what keeps AC-02-7 true of the whole app.
//

import SwiftUI

struct ContactField: View {
    /// Supplied by the caller — "Supplier" in 03, "Pelanggan" in 04.
    let label: String
    let viewModel: ContactFieldViewModel

    var body: some View {
        content
            .task { await viewModel.checkResolvable() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            // Attaching a contact is always optional (R-02-7). This state is a
            // perfectly good place to stop.
            Button {
                Task { await viewModel.pick() }
            } label: {
                LabeledContent(label) {
                    Label("Pilih dari Kontak", systemImage: "person.crop.circle.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
            }

        case .filled(let ref):
            LabeledContent(label) {
                HStack(spacing: 8) {
                    Text(ref.name)
                    detachButton
                }
            }

        case .gone(let name):
            // The contact was deleted or merged away. The snapshot still reads,
            // in secondary colour, with a quiet note and no error dialog
            // (02 §3, D-11).
            LabeledContent(label) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .foregroundStyle(.secondary)
                        detachButton
                    }
                    Text("Kontak tidak ditemukan")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var detachButton: some View {
        Button {
            viewModel.detach()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lepas kontak")
    }
}

#if DEBUG
/// Preview-only. The real fake lives in `JustScanTests/Support/`, where
/// CONVENTIONS.md requires it; a preview cannot see the test target, and this
/// stub exists so the three states can be inspected without a device.
private struct PreviewContactService: ContactServicing {
    var picked: ContactRef?
    var resolved: ContactRef?
    var authorizationStatus: ContactAccess = .granted

    @MainActor func pick() async -> ContactRef? { picked }
    func resolve(id: String) async throws -> ContactRef? { resolved }
}

private let budi = ContactRef(id: "ABC-123", name: "Budi Santoso")

#Preview("Kosong") {
    Form {
        ContactField(
            label: "Supplier",
            viewModel: ContactFieldViewModel(contacts: PreviewContactService(picked: budi))
        )
    }
}

#Preview("Terisi") {
    Form {
        ContactField(
            label: "Supplier",
            viewModel: ContactFieldViewModel(
                contacts: PreviewContactService(resolved: budi),
                ref: budi
            )
        )
    }
}

#Preview("Kontak hilang") {
    Form {
        ContactField(
            label: "Pelanggan",
            viewModel: ContactFieldViewModel(
                contacts: PreviewContactService(resolved: nil),
                ref: budi
            )
        )
    }
}
#endif

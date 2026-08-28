//
//  POSError+Message.swift
//  JustScan
//
//  Every error has a user-facing Indonesian string. An error without one is
//  a bug (foundations §7). Code and identifiers stay English; only the
//  operator-facing text is Indonesian.
//

import Foundation

extension POSError {
    /// Operator-facing message, Indonesian.
    var message: String {
        switch self {
        case .validationFailed(let field):
            return "\(Self.fieldLabel(field)) tidak valid. Periksa lagi isinya."
        case .barcodeAlreadyExists:
            return "Barcode ini sudah dipakai produk lain."
        case .productNotFound:
            return "Produk tidak ditemukan."
        case .emptyCart:
            return "Keranjang masih kosong."
        case .insufficientCash(let shortfallRp):
            return "Uang tunai kurang \(Rp.format(shortfallRp))."
        case .saleAlreadyVoided:
            return "Transaksi ini sudah dibatalkan."
        case .contactAccessDenied:
            return "Akses kontak ditolak. Aktifkan di Pengaturan."
        case .scannerUnavailable:
            return "Kamera tidak bisa dipakai. Aktifkan izin kamera di Pengaturan."
        case .persistenceFailed:
            return "Gagal menyimpan data. Coba lagi."
        }
    }

    /// Indonesian label for a field name that arrives from a service in English.
    private static func fieldLabel(_ field: String) -> String {
        switch field {
        case "name":     return "Nama"
        case "price":    return "Harga"
        case "qty":      return "Jumlah"
        case "barcode":  return "Barcode"
        case "reason":   return "Alasan"
        default:         return "Isian"
        }
    }
}

// LocalizedError so the message flows into standard SwiftUI alert presentation
// without every call site reaching for `.message`.
extension POSError: LocalizedError {
    var errorDescription: String? { message }
}

//
//  POSErrorMessageTests.swift
//  JustScanTests
//
//  Foundations §7: every error has a user-facing Indonesian string. An error
//  with no message is a bug — so the check is exhaustive over the registry.
//

import Foundation
import Testing
@testable import JustScan

struct POSErrorMessageTests {
    /// One value per case in the foundations §7 registry. Adding a case to
    /// `POSError` without adding it here leaves the new error untested, so the
    /// count assertion below is deliberate.
    private static let everyCase: [POSError] = [
        .validationFailed(field: "name"),
        .barcodeAlreadyExists(productID: UUID()),
        .productNotFound,
        .emptyCart,
        .insufficientCash(shortfallRp: 21_000),
        .saleAlreadyVoided,
        .contactAccessDenied,
        .scannerUnavailable,
        .persistenceFailed("disk full")
    ]

    @Test("Every POSError has a non-empty Indonesian message")
    func test_POSError_everyCaseHasAMessage() {
        #expect(Self.everyCase.count == 9, "The §7 registry has nine cases")
        for error in Self.everyCase {
            #expect(error.message.isEmpty == false, "\(error)")
            #expect(error.errorDescription == error.message)
        }
    }

    @Test("Messages are operator-facing Indonesian, not raw English identifiers")
    func test_POSError_messagesAreIndonesian() {
        #expect(POSError.emptyCart.message == "Keranjang masih kosong.")
        #expect(POSError.productNotFound.message == "Produk tidak ditemukan.")
        #expect(POSError.saleAlreadyVoided.message == "Transaksi ini sudah dibatalkan.")
    }

    @Test("A validation message names the field in Indonesian, not in code")
    func test_POSError_validationNamesTheFieldInIndonesian() {
        #expect(POSError.validationFailed(field: "name").message.contains("Nama"))
        #expect(POSError.validationFailed(field: "price").message.contains("Harga"))
        // An unmapped field still produces a readable sentence, never "name".
        #expect(POSError.validationFailed(field: "whatever").message.contains("Isian"))
    }

    @Test("A cash shortfall is formatted through Rp, never interpolated raw")
    func test_POSError_formatsMoneyThroughRp() {
        let message = POSError.insufficientCash(shortfallRp: 21_000).message
        #expect(message.contains("Rp 21.000"))
        #expect(message.contains("21000") == false)
    }

    @Test("A persistence failure never leaks its underlying detail to the operator")
    func test_POSError_persistenceMessageIsOperatorSafe() {
        let message = POSError.persistenceFailed("SQLITE_FULL: disk image is malformed").message
        #expect(message == "Gagal menyimpan data. Coba lagi.")
        #expect(message.contains("SQLITE") == false)
    }

    @Test("POSError is Equatable, so tests can assert on the exact case thrown")
    func test_POSError_isEquatable() {
        let id = UUID()
        #expect(POSError.barcodeAlreadyExists(productID: id) == .barcodeAlreadyExists(productID: id))
        #expect(POSError.validationFailed(field: "name") != .validationFailed(field: "price"))
    }
}

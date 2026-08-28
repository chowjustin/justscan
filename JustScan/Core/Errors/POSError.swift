//
//  POSError.swift
//  JustScan
//
//  The only error type that crosses a service boundary (R-01-5).
//  The registry is foundations §7 — no module invents its own error.
//
//  The name is deliberate: it names the domain (point of sale), not the
//  product. Product names change; the domain does not (CONVENTIONS.md).
//

import Foundation

enum POSError: Error, Equatable {
    /// A field failed its rule — name empty, price ≤ 0, qty ≤ 0.
    case validationFailed(field: String)
    /// Insert attempted for a barcode already on another non-deleted product.
    case barcodeAlreadyExists(productID: UUID)
    /// Lookup found nothing, or found a soft-deleted row (R-03-14).
    case productNotFound
    /// Tender attempted with zero lines.
    case emptyCart
    /// Cash received is less than the total.
    case insufficientCash(shortfallRp: Int)
    /// Void attempted on a sale already `voided`.
    case saleAlreadyVoided
    /// Contacts permission refused when re-resolving an identifier.
    case contactAccessDenied
    /// Camera denied, or the device does not support DataScanner.
    case scannerUnavailable
    /// A save threw. Surfaced to the operator, never swallowed.
    case persistenceFailed(String)
}

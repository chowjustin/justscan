# 01 · App Shell  [MVP]

> Build order #1 · Est. 1 session
> Depends on: nothing · Consumed by: 02, 03, 04, 05
> Code location: `App/`, `Core/`

---

## 1. Purpose & scope

Everything the other four modules stand on: the SwiftData container, the money type and its formatter, the barcode scanner wrapped as a plain Swift service, the shared error type, and the three-tab shell. This module owns no entities. It exists so that no later module has to invent infrastructure mid-build.

**Non-goals**

- No entities, no persistence models — those belong to 03 and 04.
- No business rules of any kind.
- No CloudKit container, no sync code. The schema is CloudKit-*shaped* (foundations §6), but the capability stays off.
- No design system beyond system fonts and colours. Visual polish is not this module.
- No onboarding, no settings screen.

## 2. Roles & permissions

Single operator, no auth (foundations §3). No permission matrix in this or any module.

## 3. Flows

**App launch (Operator)**
1. `ModelContainer` is built for the four model types.
2. In DEBUG, if the store is empty, `SeedService.load()` runs (foundations §9).
3. Tab shell appears with **Jual** (Sale) selected by default — the cashier screen is the app's home, not the catalogue.

**Scan a barcode (Operator)**
1. Caller invokes `ScannerService.scan()`.
2. Camera permission is checked. Denied or unsupported device → throw `scannerUnavailable`.
3. `DataScannerViewController` presents, restricted to the symbologies in R-01-6.
4. First successful read → haptic `.success`, scanner dismisses, string returned.
5. Operator cancels → returns `nil`. Cancelling is not an error.

## 4. Rules & validations

| ID | Rule |
|---|---|
| R-01-1 | Money is `Int` rupiah everywhere. `Decimal`, `Double`, and `Float` do not appear in this codebase outside SwiftUI layout code. |
| R-01-2 | `Rp.format(12000)` → `"Rp 12.000"`. Locale `id_ID`, grouping separator `.`, zero decimal places. `Rp.format(0)` → `"Rp 0"`. Negative: `Rp.format(-21000)` → `"-Rp 21.000"`. |
| R-01-3 | The `ModelContainer` is created once at app launch and injected. No type constructs its own container, except tests, which use `isStoredInMemoryOnly: true`. |
| R-01-4 | Every repository is defined by a protocol. Services depend on the protocol, never a concrete type, so tests inject fakes. |
| R-01-5 | `POSError` (foundations §7) is the only error type crossing a service boundary. A repository may throw SwiftData errors; the service wraps them in `.persistenceFailed`. |
| R-01-6 | The scanner accepts exactly: `ean13`, `ean8`, `upce`, `code128`. Any other symbology is ignored, not reported. |
| R-01-7 | `Info.plist` declares `NSCameraUsageDescription` and `NSContactsUsageDescription` in Indonesian. A missing key is a launch-time crash on first use. |
| R-01-8 | `BarcodeKind.of(_:)` classifies a scanned string: prefix `02` or `20`–`29` → `.internalCode`; 8, 12, or 13 digits otherwise → `.gtin`; anything else → `.unknown`. Used by 03 to warn the operator. |

## 5. Data model

**This module owns no entities.** It owns the container that hosts them.

```swift
@MainActor
enum PersistenceController {
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Product.self, StockMovement.self, Sale.self, SaleLine.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: config)
    }
}
```

## 6. States & transitions

None. This module holds no stateful entity.

## 7. Module contract

**Exports**

```swift
enum Rp {
    static func format(_ amount: Int) -> String
}

enum BarcodeKind { case gtin, internalCode, unknown }
extension BarcodeKind {
    static func of(_ raw: String) -> BarcodeKind
}

protocol ScannerServicing {
    func scan() async throws -> String?    // nil == operator cancelled
}

enum POSError: Error, Equatable { /* foundations §7 */ }
```

**Imports:** none.
**Internal only:** `PersistenceController`, `SeedService`, the `DataScannerViewController` UIKit wrapper. Never called from a feature module.

## 8. Edge cases

- **Camera permission denied.** `scan()` throws `scannerUnavailable`. The caller shows a message with a "Buka Pengaturan" button. The app remains fully usable — every screen that scans also has a manual path.
- **Device does not support DataScanner** (pre-A12). Same error, same handling. Never crash.
- **Scanner returns a string with whitespace or a trailing newline.** Trimmed before returning.
- **Operator scans while a scan is already presenting.** The second call returns `nil` immediately; scans do not queue.
- **Container fails to build** (corrupt store). Fatal, with the underlying error surfaced. Do not silently recreate the store — that would delete the operator's sales.

## 9. Service surface

Replaces the template's API surface: this app has no HTTP layer.

| Type | Method | Purpose | Errors |
|---|---|---|---|
| `ScannerServicing` | `scan() async throws -> String?` | Present scanner, return one code | `scannerUnavailable` |
| `Rp` | `format(_:) -> String` | Display a money amount | — |
| `BarcodeKind` | `of(_:) -> BarcodeKind` | Classify a scanned string | — |

## 10. UI notes

Three tabs, in this order, **Jual** selected on launch:

| Tab | Label (id) | Icon | Owned by |
|---|---|---|---|
| 1 | Jual | `cart` | 04 |
| 2 | Produk | `shippingbox` | 03 |
| 3 | Riwayat | `clock.arrow.circlepath` | 05 |

- System fonts. Dynamic Type supported; the sale screen must stay usable at XL sizes.
- Portrait only. This is a phone on a counter, not an iPad.
- The scanner presents as a full-screen sheet with a visible Cancel button. Never a modal the operator can be trapped in.
- All operator-facing text is Indonesian. Code, comments, and identifiers are English.

## 11. Worked examples

```
Rp.format(12000)   → "Rp 12.000"
Rp.format(0)       → "Rp 0"
Rp.format(-21000)  → "-Rp 21.000"
Rp.format(1500000) → "Rp 1.500.000"

BarcodeKind.of("8992775311011") → .gtin          (13 digits, prefix 899)
BarcodeKind.of("2011234501234") → .internalCode  (prefix 20 — variable weight)
BarcodeKind.of("0212345000129") → .internalCode  (prefix 02 — in-store)
BarcodeKind.of("12345678")      → .gtin          (8 digits, EAN-8)
BarcodeKind.of("ABC-123")       → .unknown
```

## 12. Acceptance criteria

| ID | Criterion |
|---|---|
| AC-01-1 | The app launches to the Jual tab on a fresh install without crashing. |
| AC-01-2 | `Rp.format` returns exactly the five strings in §11. |
| AC-01-3 | `BarcodeKind.of` returns exactly the five results in §11. |
| AC-01-4 | With camera permission denied, `scan()` throws `scannerUnavailable` and the app does not crash. |
| AC-01-5 | Cancelling the scanner returns `nil` and throws nothing. |
| AC-01-6 | A test can build an in-memory container and insert a `Product` without touching disk. |
| AC-01-7 | Project-wide search for `Double`, `Float`, and `Decimal` returns no hits in `Core/` or any `*Service.swift`. |
| AC-01-8 | In DEBUG on an empty store, launch produces exactly 5 products and 4 opening movements (Gorengan has none). Running seed twice still produces 5 and 4. |

## 13. Build checklist

1. Xcode project, iOS 17 target, portrait only, `Info.plist` usage strings
2. `Rp`, `BarcodeKind`, `POSError` + Indonesian messages
3. `PersistenceController` and the empty `Schema`
4. Repository protocols (empty bodies — 03 and 04 fill them)
5. `ScannerService` + `DataScannerViewController` wrapper
6. Tab shell with three placeholder screens
7. `SeedService` behind `#if DEBUG`
8. Tests for R-01-2, R-01-8, and AC-01-6

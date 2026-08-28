# 01 · App Shell  [MVP]

> Build order #1 · Est. 1 session
> Depends on: nothing · Consumed by: 02, 03, 04, 05
> Code location: `App/`, `Core/`

---

## 1. Purpose & scope

Everything the other four modules stand on: the SwiftData container, the money type and its formatter, the barcode scanner wrapped as a plain Swift service, the shared error type, and the three-tab shell. This module owns no entities. It exists so that no later module has to invent infrastructure mid-build.

**Non-goals**

- No entity *behaviour* — no rules, no validation, no mutation. Those belong to 03 and 04. The four `@Model` declarations are created here only because the `Schema` in §5 cannot exist without them (see §5).
- No business rules of any kind.
- No sync *code*, no conflict resolution, no migration tooling. The CloudKit **capability is on from session 1** (D-18) so that every launch validates the schema — but nothing in this module reads, writes, or waits on the network. See R-01-9 and `CLOUDKIT_CHECKLIST.md` Part 4.
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
| R-01-8 | `BarcodeKind.of(_:)` classifies a scanned string. A string qualifies only if it is **all digits** and 8, 12, or 13 characters long; of those, prefix `02` or `20`–`29` → `.internalCode`, otherwise `.gtin`. Everything else → `.unknown`, including a digit-prefixed non-numeric string such as `"02ABC"`. Used by 03 to warn the operator. |
| R-01-9 | Container creation attempts `cloudKitDatabase: .automatic` and, if that throws, falls back to a local-only configuration and continues. A full iCloud account, a signed-out device, or an unavailable container must **never** stop the shop trading (`CLOUDKIT_CHECKLIST.md` Part 3). The fallback is logged at `.error`; it is never silent, and it never recreates or deletes the store. |

## 5. Data model

**This module owns no entity behaviour.** It owns the container that hosts them, and the storage-only declarations that container needs.

```swift
@MainActor
enum PersistenceController {
    static let schema = Schema([Product.self, StockMovement.self, Sale.self, SaleLine.self])

    /// R-01-9: try CloudKit, fall back to local-only, never block trading.
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try container(cloudKitDatabase: .none, inMemory: true)
        }
        do {
            return try container(cloudKitDatabase: .automatic, inMemory: false)
        } catch {
            // Logged, never swallowed. The store is not recreated.
            return try container(cloudKitDatabase: .none, inMemory: false)
        }
    }
}
```

**This module owns no entities, but it does own the four `@Model` types' *declarations*** — `Product`, `StockMovement`, `Sale`, and `SaleLine` are created here as storage-only types so the `Schema` above, AC-01-6, and AC-01-8 can exist. They carry **no behaviour**: every rule, validation, and mutation belongs to 03 and 04, which own them. Fields are copied verbatim from 03 §5 and 04 §5.

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

enum JakartaDay {
    static var timeZone: TimeZone { get }          // Asia/Jakarta, always
    static func startOfDay(_ date: Date) -> Date
    static func endOfDay(_ date: Date) -> Date     // exclusive upper bound
    static func range(of date: Date) -> Range<Date>
    static func key(_ date: Date) -> String        // "YYYYMMDD", for R-04-4
    static func isSameDay(_ a: Date, _ b: Date) -> Bool
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
| `JakartaDay` | `startOfDay(_:)` / `endOfDay(_:)` / `range(of:)` | The only day-boundary helper. Nothing else computes days. | — |
| `JakartaDay` | `key(_:) -> String` | `"YYYYMMDD"` for sale numbering (R-04-4) | — |

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

Additional R-01-8 rulings, recorded so the digits-only clause is unambiguous. These are
*not* part of AC-01-3's five, but each has a test:

```
BarcodeKind.of("02ABC")         → .unknown        (prefix matches, not all digits)
BarcodeKind.of("20")            → .unknown        (prefix matches, wrong length)
BarcodeKind.of("123456")        → .unknown        (6 digits — the accepted UPC-E gap)
BarcodeKind.of("")              → .unknown
```

## 12. Acceptance criteria

| ID | Criterion |
|---|---|
| AC-01-1 | The app launches to the Jual tab on a fresh install without crashing. |
| AC-01-2 | `Rp.format` returns exactly the four strings in §11. |
| AC-01-3 | `BarcodeKind.of` returns exactly the five results in §11. |
| AC-01-4 | With camera permission denied, `scan()` throws `scannerUnavailable` and the app does not crash. |
| AC-01-5 | Cancelling the scanner returns `nil` and throws nothing. |
| AC-01-6 | A test can build an in-memory container and insert a `Product` without touching disk. |
| AC-01-7 | Project-wide search for `Double`, `Float`, and `Decimal` returns no hits in `Core/` or any `*Service.swift`. |
| AC-01-8 | In DEBUG on an empty store, launch produces exactly 5 products and 4 opening movements (Gorengan has none). Running seed twice still produces 5 and 4. |

## 13. Build checklist

1. Xcode project, iOS 17 target, portrait only, `Info.plist` usage strings, iCloud capability (D-18)
2. `Rp`, `BarcodeKind`, `JakartaDay`, `POSError` + Indonesian messages
3. The four storage-only `@Model` types, `PersistenceController` and its `Schema`
4. Repository protocols + their SwiftData conformances, limited to what the seed and 03 §7 already name
5. `ScannerService` + `DataScannerViewController` wrapper
6. Tab shell with three placeholder screens
7. `SeedService` behind `#if DEBUG`
8. Tests for R-01-2, R-01-8, JakartaDay, AC-01-6, and AC-01-8

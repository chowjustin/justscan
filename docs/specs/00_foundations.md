# 00 · Foundations

> The document every other spec leans on. Re-read this at the start of every build session.
> Project: **JustScan** · Bundle ID: `chow.JustScan` · CloudKit container: `iCloud.chow.JustScan` · Platform: iOS 17+ · Single device, CloudKit-mirrored.

---

## 1. Product thesis

An iOS point-of-sale app for a single small Indonesian shop, operated by one person who is both owner and cashier. The owner builds their product catalogue by scanning the barcodes already printed on stock they own, rather than typing a catalogue from scratch, and rings up a sale on one screen without ever navigating away. **The name is the promise: you just scan.** A scan is the primary gesture in both halves of the app — it is how a product enters the catalogue and how it enters a cart, and in both cases the same scan is idempotent (open the existing thing, or create it). Any feature that makes the operator type where they could have scanned is working against the product. Its wedge over Moka and Majoo is that setup takes minutes instead of an afternoon, supplier and customer identity comes from the phone's own Contacts rather than a data-entry form, and every stock and money movement is append-only, so "why is my stock wrong" is a question the app can actually answer.

---

## 2. Glossary & naming map

Domain vocabulary in the user's own language, with the code identifier that must be used everywhere. Do not invent synonyms.

| Term | Means | Code identifier |
|---|---|---|
| Product | One sellable item at one price. Different sizes are different products. | `Product` |
| Barcode | The GTIN printed on packaging, scanned by camera | `Product.barcode` |
| Stock movement | One append-only change to a product's quantity, with a reason | `StockMovement` |
| Stock | Current quantity on shelf; the sum of all movements | `Product.stockQty` (cached) |
| Restock | Adding stock bought from a supplier | `StockReason.restock` |
| Adjustment | Correcting stock for expiry, loss, or miscount | `StockReason.adjustment` |
| Sale | One completed transaction, one payment | `Sale` |
| Line | One product within a sale | `SaleLine` |
| Cart | A sale in progress, before payment | `SaleDraft` (in-memory, never persisted) |
| Tender | Taking payment and closing the sale | `SaleService.complete(...)` |
| Void | Reversing a completed sale; never a delete | `Sale.status = .voided` |
| Supplier | Who the owner buys from — a phone contact | `Product.supplierContactID` |
| Customer | Who the owner sells to — an optional phone contact | `Sale.customerContactID` |
| QRIS | Indonesian standard payment QR, static, taped to counter | `PaymentMethod.qris` |

---

## 3. Actors & role model

**One actor: the Operator.** Owner and cashier are the same person (DECISIONS D-01). There is no login, no role column, no permission check anywhere in this system.

Consequence, stated so it is not discovered later: this system has **no fraud controls**. Anyone holding the unlocked phone can void a sale, change a price, or adjust stock. This is acceptable for an owner-operated shop and unacceptable the moment a second person is employed. Adding staff means adding roles, and roles are a full module — it is in the deferral register, not a small change.

---

## 4. Entity map

The master list. **If an entity is not in this table, it does not exist.**

| Entity | Owned by | One-line purpose |
|---|---|---|
| `Product` | 03 catalogue | One sellable item at one price |
| `StockMovement` | 03 catalogue | One append-only change to a product's quantity |
| `Sale` | 04 sale | One completed transaction with one payment |
| `SaleLine` | 04 sale | One product within a sale, with price snapshotted |

**Not entities:**

- `ContactRef` — a pair of fields (`contactID: String?`, `contactName: String?`) embedded on `Product` and `Sale`. Never its own table. Module 02 owns the code that produces it.
- `SaleDraft` — the in-progress cart. Lives in the ViewModel only, never persisted. An app crash mid-sale loses the cart; this is intentional (§9).

---

## 5. Module map & build order

A module is not started until every module it depends on is done.

| # | Module | Depends on | Why it sits here |
|---|---|---|---|
| 01 | App shell | — | Store, money type, scanner, error types. Nothing works without it. |
| 02 | Contact link | 01 | Cross-cutting and headless. Built before 03 and 04 both need it. |
| 03 | Catalogue | 01, 02 | Owns `Product` and `StockMovement`. Sales cannot exist without products. |
| 04 | Sale | 01, 02, 03 | Owns the transaction. Needs a catalogue to sell from. |
| 05 | History | 03, 04 | Read-only over everything above. Always last. |

Estimated one focused build session per module, five sessions total.

---

## 6. Conventions

Shared decisions every module inherits. Given as literal shapes, not descriptions.

### IDs
UUID v4, generated app-side in the property default: `var id: UUID = UUID()`. Never rely on SwiftData's implicit identity — it is not stable across a CloudKit sync.

### Money
**Integer rupiah. No `Decimal`, no `Double`, no floats anywhere in this codebase.** IDR has no circulating subunit, so an `Int` is exact and needs no scaling factor.

- Field naming: always suffix `Rp` — `priceRp`, `totalRp`, `changeRp`.
- Display: `Rp 12.000` — thousands separated with `.`, no decimal places, `id_ID` locale.
- A negative money field is always a deliberate reversal, never an error state.

### Time
- Stored as `Date` (UTC internally, which is what `Date` already is).
- Displayed and **grouped by day** in `Asia/Jakarta` (WIB, UTC+7). "Today's sales" means today in Jakarta, not today in UTC. This matters: a sale at 08:00 WIB is 01:00 UTC the same day, but a sale at 06:00 UTC is 13:00 WIB — grouping on the wrong zone splits a trading day in half.
- Every entity carries `createdAt: Date = Date()`.

### SwiftData model rules — mandatory, no exceptions
Written this way from day one so the schema never has to change. Violating any of these throws `NSCocoaErrorDomain 134060` at store load, naming the exact offending fields — loud and specific, but only once a CloudKit-backed container is actually configured. Full rules, enablement steps, and costs: `CLOUDKIT_CHECKLIST.md`.

| Rule | Why |
|---|---|
| Every stored property is optional **or** has a default value | CloudKit requirement |
| **Never** use `@Attribute(.unique)` | CloudKit does not support unique constraints |
| Every relationship is optional (`[Child]?`, `Parent?`) | CloudKit syncs object graphs partially |
| Every relationship declares an explicit `inverse:` | Required, and its absence crashes on some iOS versions |
| Delete rules are `.cascade` or `.nullify` — never `.deny` | CloudKit requirement |
| Deletion is soft: set `deletedAt`, never `modelContext.delete()` | Hard deletes do not propagate reliably |
| No ordered relationships; sort with an explicit `SortDescriptor` | CloudKit requirement |
| Enums stored as raw `String` with an explicit unknown-value fallback | Schema evolution safety |

**Uniqueness is enforced in the repository layer, not the schema.** `ProductRepository.findBy(barcode:)` runs before every insert. See ADR-02.

### Layering
```
View  →  ViewModel  →  Service  →  Repository  →  ModelContext
```
- A View **never** imports SwiftData, touches `ModelContext`, or does arithmetic on money.
- A ViewModel **never** touches `ModelContext` — it calls Services only.
- A Service holds all business rules and is the only place a rule may live.
- A Repository does fetch/insert/save and nothing else. No rules, no validation.
- **We do not use `@Query` in views.** It is idiomatic SwiftUI but it welds the view to the store and makes the rules untestable. This is a deliberate, recorded trade-off (ADR-03) — do not "fix" it.

### Naming
Swift standard: `UpperCamelCase` types, `lowerCamelCase` properties, models named singular (`Product`, not `Products`). Services are `<Noun>Service`, repositories `<Noun>Repository`. One type per file, filename matches the type.

### Cross-module calls
There is no event bus. Modules call each other through the exported service interfaces listed in each spec's §7. Direct calls are correct at this size; an event bus for a five-module single-device app is architecture for a scale that does not exist.

Module 01 is ambient — every module uses `Rp`, `POSError`, and `ScannerService`, and those are not listed as dependencies here.

| Caller | Callee | Purpose |
|---|---|---|
| 03 catalogue | 02 contact | Attach a supplier to a product |
| 04 sale | 03 catalogue | Look up product by barcode; record stock movements |
| 04 sale | 02 contact | Attach a customer to a sale |
| 05 history | 04 sale | Read sales; request a void |

### Logging
Log every stock movement and every sale state change with its ID at `.info`. **Never log** contact names, contact identifiers, or full customer records.

---

## 7. Error registry

One Swift error type for the whole app. Every module raises from this list; no module invents its own.

```swift
enum POSError: Error, Equatable {
    case validationFailed(field: String)
    case barcodeAlreadyExists(productID: UUID)
    case productNotFound
    case emptyCart
    case insufficientCash(shortfallRp: Int)
    case saleAlreadyVoided
    case contactAccessDenied
    case scannerUnavailable
    case persistenceFailed(String)
}
```

| Code | Meaning | Raised by |
|---|---|---|
| `validationFailed` | A field failed its rule — name empty, price ≤ 0, qty ≤ 0 | all |
| `barcodeAlreadyExists` | Insert attempted for a barcode already on another product | 03 |
| `productNotFound` | Lookup found nothing, or found a soft-deleted row (R-03-14) | 03 |
| `emptyCart` | Tender attempted with zero lines | 04 |
| `insufficientCash` | Cash received is less than the total | 04 |
| `saleAlreadyVoided` | Void attempted on a sale already `voided` | 04, 05 |
| `contactAccessDenied` | Contacts permission refused when re-resolving an identifier | 02 |
| `scannerUnavailable` | Camera denied, or device does not support DataScanner | 01 |
| `persistenceFailed` | Save threw. Surfaced to the user, never swallowed | all |

Every error has a user-facing Indonesian string in `POSError+Message.swift`. An error with no message is a bug.

---

## 8. Non-functional targets

Stated honestly so nothing is over-built.

| Dimension | Target | Consequence |
|---|---|---|
| Users | 1 | No auth, no roles, no multi-tenancy, no scope filters |
| Devices | 1 | No sync, no conflict resolution, no idempotency keys |
| Products | 200–2,000 | An in-memory filter over all products is fine. Do not build search indexing. |
| Sales | ~50/day, ~18,000/year | `stockQty` is cached because summing movements per row per render is not |
| Scan → line on screen | < 300 ms | The one performance number that matters. Nothing else is measured. |
| Offline | **Always.** Every read and write is local and synchronous. CloudKit mirrors in the background and is never on a user-facing path. | No loading spinners on any data path. A dead network changes nothing. |
| Backup | None in MVP | See deferral register — iCloud is why the schema rules in §6 exist |

**What this section forbids:** background sync, retry queues, idempotency keys, outbox tables, pagination, caching layers, search indexes. If a build session proposes any of these, it has drifted.

---

## 9. Seed data

The dataset the app boots with in DEBUG. Real Indonesian products with real barcodes and plausible prices.

**Products**

| Name | Barcode | Price | Opening stock | Supplier |
|---|---|---|---|---|
| Chitato Sapi Panggang 68g | `8992775311011` | 12000 | 24 | Toko Grosir Budi |
| Teh Botol Sosro 350ml | `8992772000108` | 5000 | 12 | Toko Grosir Budi |
| Indomie Goreng 85g | `8998866200608` | 3500 | 40 | Toko Grosir Budi |
| Aqua 600ml | `8886008101053` | 4000 | 24 | — |
| Gorengan (per pcs) | *(none)* | 2000 | 0 | — |

`Gorengan` exists in the seed on purpose: it is the barcode-less, stock-less case, and every screen must handle it without a special path.

**Stock movements:** one `opening` movement per product **with stock above zero** — four movements (`+24`, `+12`, `+40`, `+24`). `Gorengan` gets none: zero stock is the absence of movements, never a movement of zero (R-03-9, R-03-13).

**Sales:** none. The golden path creates the first one.

A `SeedService.load()` runs only in DEBUG, only into an empty store, and is idempotent.

---

## 10. Golden path

The end-to-end smoke test. If this runs clean, the system works. Numbers are exact and tests are written from them.

```
 1. Fresh install, empty catalogue. Operator opens Catalogue.

 2. Scan 8992775311011 → not found → new product form opens, barcode prefilled.
    Enter "Chitato Sapi Panggang 68g", price 12000, supplier picked from
    Contacts → "Toko Grosir Budi". Save.
    → Product created, stockQty 0, no movement written.

 3. Product detail → Add stock → 24.
    → StockMovement(+24, restock). stockQty = 24.

 4. Scan 8992772000108 → not found → "Teh Botol Sosro 350ml", 5000, no
    supplier. Save. Add stock 12. stockQty = 12.

 5. Open Sale screen. Scan 8992775311011 → line appended, qty 1.
    Scan it again → SAME line, qty becomes 2. Subtotal 24000.
    Scan 8992772000108 → second line, qty 1.
    → Total 12000×2 + 5000×1 = 29000.

 6. Tender → Cash → cash received 50000.
    → Change due 21000, shown large.
    → Sale 20260821-001 completed, paymentMethod cash.
    → StockMovement(-2, sale, saleID) and (-1, sale, saleID) written.
    → Chitato stockQty 22, Teh Botol 11.
    → Screen resets to an empty cart in under 1 second.

 7. History → today: 1 sale, total 29000, cash 29000, QRIS 0.

 8. Open sale 20260821-001 → Void, reason "salah barang".
    → Sale.status = voided, voidedAt set. Number 20260821-001 RETAINED.
    → StockMovement(+2, void, saleID) and (+1, void, saleID) written.
    → Chitato stockQty back to 24, Teh Botol back to 12.

 9. History → today: 0 sales counted, total 0. The voided sale is still
    listed, struck through.

10. Chitato detail → movement history shows, newest first:
    +2 void · -2 sale · +24 restock · +0 opening.
    Tap "Recompute from movements" → stockQty recomputes to 24. Unchanged.
```

---

## 11. Deferral register

Every `[Later]` item, with the trigger that brings it back.

| Item | Why deferred | Bring back when |
|---|---|---|
| iCloud backup / sync | One device today. Schema is already compatible (§6). | Owner gets a second device, or asks for backup |
| Staff accounts & roles | One operator. Full module, not a small change. | A second person is employed |
| Receipt printing | Verbal totals work at this size | Customers ask for receipts, or tax requires it |
| Shift open/close, Z-report | Only meaningful with staff to hold accountable | Staff exist |
| Discounts | Owner discounts by editing the price mentally | Owner asks twice |
| PPN / tax lines | Below the threshold where it applies | Business is registered for PPN |
| Partial refund of single lines | Whole-sale void covers every case seen so far | A real partial-return case appears |
| Product photos & categories | 200 products is scrollable and searchable by name | Catalogue passes ~300 products |
| QRIS gateway integration | Static QR + manual confirmation is how these shops already work | Volume makes manual confirmation the bottleneck |
| Multi-barcode per product | One code per product covers packaged goods | Owner stocks the same item in inner-pack and box |

---

## 12. Architecture decision records

Three ADRs sit in `docs/adr/`. Summarised here; the full context lives in the ADR files.

| ID | Decision | Consequence accepted |
|---|---|---|
| ADR-01 | SwiftData over Core Data and GRDB | Lightweight migrations only; eager loading on large graphs. Repository layer keeps the swap open. |
| ADR-02 | Repository-enforced uniqueness over `@Attribute(.unique)` | Uniqueness is only as good as the discipline of routing every insert through the repository. Bought: CloudKit compatibility. |
| ADR-03 | MVVM + `@Observable`, no `@Query` in views, no TCA | More wiring per screen than plain SwiftUI. Bought: services testable without a UI, and no third-party framework to learn. |

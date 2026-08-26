# 04 · Sale  [MVP]

> Build order #4 · Est. 1 session (the largest module — build nothing else this session)
> Depends on: 01, 02, 03 · Consumed by: 05 history
> Code location: `Features/Sale/`

---

## 1. Purpose & scope

The cashier screen and the money. Owns `Sale` and `SaleLine`, the tender flow for Cash and QRIS, and the void that reverses a completed sale in both money and stock.

**The pivot event is tender.** Before tender, the cart is in-memory and free — add, remove, change quantity, discard. At tender, everything persists at once: the sale, its lines with prices snapshotted, and the stock movements. After tender, the sale is immutable; the only permitted change is a void, which writes new rows and never edits old ones.

The screen must never navigate away from itself during a normal sale. That constraint drives every UI decision here.

**Non-goals**

- No discounts, no promo codes, no tax lines. `[Later]`
- No split tender. One sale, one payment method.
- No partial refund of individual lines. Whole-sale void only. `[Later]`
- No receipt printing, no email, no SMS. `[Later]`
- No QRIS gateway, no callback, no payment verification. Static QR, manual confirmation.
- No held/parked sales. One cart at a time. `[Later]`
- Does not write `stockQty`. It calls `StockServicing.record` and nothing else.

## 2. Roles & permissions

Single operator. Note explicitly: **void has no approval step** — there is nobody to approve it (foundations §3). This is the sharpest edge of the no-roles decision and it is accepted.

## 3. Flows

**Ring up a sale (Operator) — the main flow**
1. Jual tab opens with an empty cart and the scanner button prominent.
2. Scan → `CatalogueService.findBy(barcode:)`.
3. **Found, not already in cart** → append a line, qty 1, price snapshotted from the product now.
4. **Found, already in cart** → increment that line's qty. Do **not** append a duplicate line (R-04-2).
5. **Not found** → inline banner: *"Produk tidak dikenal"* + "Tambah Produk Baru". Cart is untouched. The operator can keep scanning other items.
6. If `product.stockQty <= 0`, show a non-blocking warning on that line. **The sale always proceeds** (R-04-6, D-05).
7. Running total updates on every change, always visible without scrolling.
8. Operator may: tap a line to edit qty, swipe to delete a line, or discard the whole cart (with confirmation, only if non-empty).
9. Optionally attach a customer via `ContactField`.

**Tender — cash (Operator)**
1. Tap **Bayar**. Empty cart → button is disabled; `emptyCart` is the service-level guard.
2. Tender sheet: total in large type, method selector `Tunai | QRIS`, Tunai preselected.
3. Enter cash received. Quick-pick chips for common notes rounded up from the total (R-04-9).
4. Cash < total → confirm disabled, shortfall shown. `insufficientCash` is the service-level guard.
5. Confirm → `SaleService.complete(...)`, one transaction:
   a. Allocate `number` (R-04-4)
   b. Insert `Sale` with `status = .completed`
   c. Insert every `SaleLine` with snapshots
   d. For each line, `StockService.record(delta: −qty, reason: .sale, saleID:)`
   e. Save once
6. Success screen: **change due**, large. Auto-dismisses after 3 s, or on tap.
7. Cart resets to empty. Screen is ready for the next customer in **under 1 second**.

**Tender — QRIS (Operator)**
1. Same sheet, method `QRIS`.
2. No amount entry. QRIS is exact by construction: `cashReceivedRp = nil`, `changeRp = nil`.
3. Confirm means *"I saw the payment succeed on the customer's phone."*
4. Same commit sequence. Success screen shows "Lunas — QRIS", no change amount.

**Void a completed sale (Operator)**
1. Entered from 05 history, sale detail → **Batalkan**.
2. Confirm sheet, reason required, free text, 1–120 chars.
3. `SaleService.void(...)`, one transaction:
   a. `status = .voided`, `voidedAt = .now`, `voidReason` set
   b. For each line, `StockService.record(delta: +qty, reason: .void, saleID:)`
   c. Save once
4. The number is **retained**. Nothing is deleted.

## 4. Rules & validations

| ID | Rule |
|---|---|
| R-04-1 | The cart is in-memory only (`SaleDraft` in the ViewModel). Nothing persists before tender. Backgrounding is safe; a force-quit or crash loses the cart, which is accepted (foundations §4). |
| R-04-2 | Scanning a product already in the cart **increments the existing line**. A sale never contains two lines for the same `productID`. |
| R-04-3 | `SaleLine` snapshots `nameSnapshot` and `unitPriceRp` at tender. Later catalogue edits, and even soft-deleting the product, never alter a completed sale. This is the load-bearing rule of the whole system. |
| R-04-4 | `Sale.number` is `{YYYYMMDD}-{NNN}` in `Asia/Jakarta`, e.g. `20260821-007`. `NNN` is zero-padded, restarts at `001` each Jakarta day, and is allocated as `count(sales that Jakarta day) + 1`. Voided sales keep their number and still consume it — **gaps are not permitted, reuse is not permitted.** |
| R-04-5 | `lineTotalRp = unitPriceRp × qty`. `Sale.totalRp = Σ lineTotalRp`, stored, not computed at read time. |
| R-04-6 | Insufficient stock **never** blocks a sale. Warn on the line, complete the sale, let `stockQty` go negative (R-03-7). A shop that cannot sell what is physically in the customer's hand is broken. |
| R-04-7 | Tender with zero lines throws `emptyCart`. |
| R-04-8 | Cash: `cashReceivedRp >= totalRp` or throw `insufficientCash(shortfallRp:)`. `changeRp = cashReceivedRp − totalRp`. |
| R-04-9 | Cash quick-picks are the total rounded up to the next 5.000, 10.000, 20.000, 50.000, and 100.000, deduplicated, excluding any equal to the total. Plus an exact-amount chip. |
| R-04-10 | QRIS: `cashReceivedRp` and `changeRp` are both `nil`. Never `0` — nil means "not applicable", zero means "no change was due", and conflating them corrupts reporting. |
| R-04-11 | A completed sale is immutable except for the void fields. No line may be added, removed, or re-priced after tender. |
| R-04-12 | Void is idempotent-guarded: voiding an already-voided sale throws `saleAlreadyVoided`. |
| R-04-13 | A void writes exactly one `+qty` `.void` movement per original line, carrying the same `saleID`. Money and stock reverse together or neither does. |
| R-04-14 | `voidReason` is required, trimmed, 1–120 chars. A void with no reason is a void nobody can explain later. |
| R-04-15 | Sale commit and void commit are each **one** `save()`. A partial write — sale persisted, movements not — is the worst bug this system can have. |
| R-04-16 | `qty` is an `Int` ≥ 1. Reducing a line to 0 removes the line. |

## 5. Data model

### `Sale`

| Field | Type | Null | Default | Notes |
|---|---|:--:|---|---|
| `id` | `UUID` | ✗ | `UUID()` | PK |
| `number` | `String` | ✗ | `""` | `{YYYYMMDD}-{NNN}`, R-04-4 |
| `totalRp` | `Int` | ✗ | `0` | stored Σ of lines |
| `paymentMethodRaw` | `String` | ✗ | `"cash"` | `cash` \| `qris` |
| `cashReceivedRp` | `Int?` | ✓ | `nil` | cash only |
| `changeRp` | `Int?` | ✓ | `nil` | cash only |
| `customerContactID` | `String?` | ✓ | `nil` | from 02 |
| `customerName` | `String?` | ✓ | `nil` | snapshot, paired |
| `statusRaw` | `String` | ✗ | `"completed"` | `completed` \| `voided` |
| `voidedAt` | `Date?` | ✓ | `nil` | |
| `voidReason` | `String?` | ✓ | `nil` | required when voided |
| `createdAt` | `Date` | ✗ | `Date()` | tender time |
| `lines` | `[SaleLine]?` | ✓ | `[]` | `.cascade`, inverse `\SaleLine.sale` |

### `SaleLine`

| Field | Type | Null | Default | Notes |
|---|---|:--:|---|---|
| `id` | `UUID` | ✗ | `UUID()` | PK |
| `sale` | `Sale?` | ✓ | `nil` | inverse `\Sale.lines` |
| `productID` | `UUID?` | ✓ | `nil` | **weak reference — no relationship.** Deleting a product must not cascade into sales history |
| `nameSnapshot` | `String` | ✗ | `""` | R-04-3 |
| `unitPriceRp` | `Int` | ✗ | `0` | R-04-3 |
| `qty` | `Int` | ✗ | `1` | ≥ 1 |
| `lineTotalRp` | `Int` | ✗ | `0` | stored, = `unitPriceRp × qty` |

```swift
enum PaymentMethod: String { case cash, qris }
enum SaleStatus: String { case completed, voided }
```

`productID` is deliberately a plain `UUID?` and **not** a SwiftData relationship. A relationship would make the delete rule between `Product` and `SaleLine` a decision that could go wrong; a weak ID makes it impossible for a product deletion to touch financial history.

## 6. States & transitions

**Sale:** `completed → voided` (operator, with a reason).
Terminal: `voided`. Irreversible — there is no un-void. To correct a mistaken void, ring the sale up again.
`SaleDraft` is not an entity and has no persisted state.

## 7. Module contract

**Exports**

```swift
protocol SaleServicing {
    func complete(lines: [DraftLine],
                  method: PaymentMethod,
                  cashReceivedRp: Int?,
                  customer: ContactRef?) throws -> Sale
    func void(_ sale: Sale, reason: String) throws
    func sales(onJakartaDay day: Date) throws -> [Sale]
    func allSales(limit: Int, offset: Int) throws -> [Sale]   // newest first
}

struct DraftLine: Equatable {
    let productID: UUID
    let name: String
    let unitPriceRp: Int
    var qty: Int
    var lineTotalRp: Int { unitPriceRp * qty }
}
```

**Imports**

```
CatalogueService.findBy(barcode:)                 // 03 — scan lookup
StockService.record(product:delta:reason:saleID:)  // 03 — the ONLY stock path
ScannerService.scan()                              // 01
ContactService.pick()                              // 02 — optional customer
Rp.format(_:)                                      // 01
```

**Internal only:** `SaleRepository`, number allocation, the tender state machine. Module 05 reads sales and requests voids through `SaleServicing`; it never writes.

## 8. Edge cases

- **Same product scanned five times.** One line, `qty 5` (R-04-2).
- **Unknown barcode mid-sale.** Banner offers "Tambah Produk Baru". Taking it navigates away and **discards the cart** — so the banner must say so. Alternative accepted for MVP: the operator finishes the sale first, then adds the product. Do not build a cart-preserving detour.
- **Line reduced to qty 0.** Line is removed (R-04-16).
- **All lines removed.** Cart is empty, Bayar disables, screen returns to its empty state.
- **Cash exactly equal to total.** `changeRp = 0`. Valid, and distinct from QRIS's `nil` (R-04-10).
- **Cash overpay of 1.000.000 on a 29.000 sale.** Allowed. Change 971.000. Not this app's business to police.
- **Product soft-deleted between adding to cart and tendering.** The sale completes. Lines are snapshots; the stock movement still records against the deleted product's ledger.
- **Product price edited in another tab mid-cart.** The cart keeps the price captured at scan time. The line was quoted to the customer; honour the quote.
- **Tender at 23:59:58 WIB, commit lands at 00:00:01 WIB.** The number is allocated from `createdAt`. Same instant, same day, consistent number and grouping. Allocate `createdAt` **once**, at the start of `complete`, and use that single value for the number, the sale, and every movement.
- **Two sales in the same second.** Numbering counts existing rows for the day; the commit is serialised on `@MainActor`. Single device, no concurrency.
- **Void a sale whose product no longer exists.** Money reverses. Stock reverses onto the soft-deleted product's ledger, which is correct and harmless.
- **Void twice** (double tap, or from two screens). Second throws `saleAlreadyVoided`.
- **Crash between insert and save.** SwiftData rolls back. R-04-15 is what makes this true — one save, not several.
- **Cart of 40 lines.** No pagination. Foundations §8 says this is not a scale we build for.

## 9. Service surface

| Type | Method | Purpose | Errors |
|---|---|---|---|
| `SaleServicing` | `complete` | Tender and commit | `emptyCart`, `insufficientCash`, `validationFailed`, `persistenceFailed` |
| `SaleServicing` | `void` | Reverse money and stock | `saleAlreadyVoided`, `validationFailed`, `persistenceFailed` |
| `SaleServicing` | `sales(onJakartaDay:)` | Day's sales for 05 | `persistenceFailed` |
| `SaleServicing` | `allSales(limit:offset:)` | History list for 05 | `persistenceFailed` |

## 10. UI notes

**Jual — one screen, and it never leaves itself.**

Vertical layout, top to bottom:

| Region | Content |
|---|---|
| Top | Cart lines, scrollable. Newest **at the top** — the operator watches the thing they just scanned appear where their eye already is. |
| Line row | Name · `qty × unitPrice` · line total, right-aligned. Red "Stok habis" chip when the product's stock ≤ 0. Tap → qty stepper. Swipe → delete. |
| Bottom bar, fixed | **Total** in the largest type on the screen. Below it: a full-width **Scan** button and a **Bayar** button. Both reachable one-handed, in the bottom third. |
| Empty state | "Scan barang untuk mulai" and the scan button. No illustration, no empty-state art. |

**Tender sheet** — total, `Tunai | QRIS` segmented control, cash field with quick-pick chips, confirm.
**Success** — change due in the largest type the screen allows, or "Lunas — QRIS". Auto-dismiss 3 s.
**Void sheet** — sale summary, required reason field, destructive confirm.

Rules that are not negotiable:
- Scan → line visible in **under 300 ms** (foundations §8). No animation may sit in that path.
- Tender → empty cart in **under 1 second**.
- Success haptic on line add (`.success`) and on tender complete (`.success`). Warning haptic on unknown barcode.
- No modal may block scanning except the tender sheet itself.

## 11. Worked examples

```
SALE — CASH
  Chitato Sapi Panggang 68g   12.000 × 2  =  24.000
  Teh Botol Sosro 350ml        5.000 × 1  =   5.000
  ──────────────────────────────────────────────────
  Total                                      29.000

  Quick-picks for 29.000  →  30.000 · 40.000 · 50.000 · 100.000 · Pas (29.000)
    (30.000 from round-up-to-5k and round-up-to-10k, deduplicated)

  Cash received 50.000  →  change 21.000
  Sale 20260821-001, method cash, cashReceivedRp 50000, changeRp 21000
  Movements: Chitato −2 (sale), Teh Botol −1 (sale)
  Stock: Chitato 24 → 22, Teh Botol 12 → 11

SALE — QRIS, same cart
  Sale 20260821-002, method qris, cashReceivedRp nil, changeRp nil
  Movements identical. nil is not 0.

VOID of 20260821-001, reason "salah barang"
  Sale.status → voided, voidedAt set, number 20260821-001 RETAINED
  Movements: Chitato +2 (void, saleID), Teh Botol +1 (void, saleID)
  Stock: Chitato 22 → 24, Teh Botol 11 → 12
  Chitato ledger now reads: +24 restock, −2 sale, +2 void  → 24

NUMBERING ACROSS A DAY BOUNDARY (Asia/Jakarta)
  2026-08-21 23:58 WIB  → 20260821-007
  2026-08-22 00:03 WIB  → 20260822-001     (restarts)
  Void 20260821-007. The next sale on 21 Aug is still -008. No reuse.

INSUFFICIENT CASH
  Total 29.000, cash received 25.000
  → insufficientCash(shortfallRp: 4000)
  → UI: "Kurang Rp 4.000". Confirm stays disabled. Nothing is written.

STOCK GOES NEGATIVE
  Teh Botol stockQty 0. Operator scans it, sells 3.
  → Warning chip on the line. Sale completes. Movement −3.
  → stockQty = −3, shown in red on the product screen.
  The shop sold three bottles. The ledger now says so.
```

## 12. Acceptance criteria

| ID | Criterion |
|---|---|
| AC-04-1 | Scanning the same product twice yields one line with `qty == 2`. |
| AC-04-2 | Scanning an unknown barcode leaves the cart unchanged and shows the banner. |
| AC-04-3 | `complete` with zero lines throws `emptyCart`; nothing is persisted. |
| AC-04-4 | Cash below total throws `insufficientCash` with the exact shortfall; nothing is persisted. |
| AC-04-5 | A cash sale of 29.000 with 50.000 received stores `changeRp == 21000`. |
| AC-04-6 | A QRIS sale stores `cashReceivedRp == nil` and `changeRp == nil`, not `0`. |
| AC-04-7 | The first sale of a Jakarta day is numbered `{YYYYMMDD}-001`; the eighth is `-008`. |
| AC-04-8 | Voiding a sale does not free its number; the next sale that day still increments. |
| AC-04-9 | `complete` writes exactly one `.sale` movement per line, each carrying the sale's ID. |
| AC-04-10 | `void` writes exactly one `.void` movement per line, restoring every product to its pre-sale quantity. |
| AC-04-11 | Voiding a voided sale throws `saleAlreadyVoided` and writes nothing. |
| AC-04-12 | Voiding with an empty reason throws `validationFailed(field: "reason")`. |
| AC-04-13 | Editing a product's price after a sale leaves that sale's `totalRp` and `unitPriceRp` unchanged. |
| AC-04-14 | Soft-deleting a product after a sale leaves the sale's `nameSnapshot` rendering correctly in history. |
| AC-04-15 | Selling a product with `stockQty == 0` completes the sale and results in negative stock. |
| AC-04-16 | A forced failure inside `complete` leaves zero sales, zero lines, and zero movements — no partial write. |
| AC-04-17 | Project-wide, `stockQty` is never assigned inside `Features/Sale/`. |
| AC-04-18 | After tender, the cart is empty and the screen is interactive within 1 second. |

## 13. Build checklist

1. `Sale` + `SaleLine` models, CloudKit rules verified
2. `SaleRepository` + number allocation (R-04-4), tested across a day boundary
3. `SaleService.complete` — single-transaction commit, R-04-15 first, before any UI
4. `SaleService.void` — reversal, R-04-13
5. `SaleDraft` / `SaleViewModel` — the in-memory cart with R-04-2 merge
6. Cart screen: lines, running total, scan and pay buttons
7. Tender sheet: method selector, cash entry, quick-picks (R-04-9)
8. Success screen with change due, auto-dismiss, reset
9. Void sheet with required reason
10. Tests for every `R-04-*` and `AC-04-*`. **Write AC-04-16 first** — it is the one that protects the money.

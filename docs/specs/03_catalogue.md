# 03 · Catalogue  [MVP]

> Build order #3 · Est. 1 session
> Depends on: 01 app shell, 02 contact link · Consumed by: 04 sale, 05 history
> Code location: `Features/Catalogue/`, `Core/Stock/`

---

## 1. Purpose & scope

Owns `Product` and `StockMovement` — the entire product master and the append-only ledger that explains every quantity in it. The defining interaction is **scan-to-add**: one scan either opens an existing product or opens a prefilled new-product form, never both and never a duplicate.

`Product.stockQty` is a **cache**. The ledger is the truth. Every quantity change in the entire app goes through `StockService`; nothing else may assign to `stockQty`.

**Non-goals**

- Does not sell anything. Deducting stock at checkout is triggered by 04 calling in.
- No purchase orders, no supplier invoices, no cost price, no margin.
- No categories, no photos, no variants, no units of measure. `[Later]`
- No multi-barcode per product. One nullable code. `[Later]`
- Does not validate a barcode's check digit. A code that scans is a code we accept.
- No stock-take / bulk-count mode. Adjustments are one product at a time.

## 2. Roles & permissions

Single operator. Everything in this module is available to them.

## 3. Flows

**Scan-to-add (Operator) — the pivot flow**
1. Operator taps Scan on the Produk tab.
2. `ScannerService.scan()` returns a code, or `nil` (cancelled → stop, no state change).
3. `ProductRepository.findBy(barcode:)`, ignoring soft-deleted rows.
4. **Found** → push that product's detail screen. Stop.
5. **Not found** → push the new-product form with `barcode` prefilled and locked.
6. If `BarcodeKind.of(code) == .internalCode`, show the R-03-8 warning inline **above** the form. The operator may proceed anyway.
7. Operator enters name and price, optionally picks a supplier via `ContactField`.
8. Save → `CatalogueService.create(...)` re-checks the barcode inside the same call (R-03-2), inserts, and returns the product.
9. New products start at `stockQty = 0` with **no** movement written. Zero stock is the absence of movements, not a movement of zero.

**Add stock (Operator)**
1. Product detail → "Tambah Stok" → number pad, default 1.
2. Confirm → `StockService.record(product:delta:+n, reason: .restock)`.
3. Movement is inserted and `stockQty` is incremented **in the same transaction** (R-03-11).

**Adjust stock (Operator)**
1. Product detail → "Koreksi Stok".
2. Operator enters the **actual counted quantity**, not a delta, plus a reason: `Kedaluwarsa` / `Hilang` / `Salah hitung`.
3. Service computes `delta = counted − stockQty` and records it as `.adjustment` with the reason as `note`.
4. `delta == 0` → no movement written, sheet dismisses. Recording a no-op pollutes the ledger.

**Recompute (Operator)**
1. Product detail → menu → "Hitung Ulang dari Riwayat".
2. `StockService.recompute(product:)` sums every movement and overwrites `stockQty`.
3. Show the before/after. If they differ, that is a cache bug — surface it, do not hide it.

**Delete a product (Operator)**
1. Product detail → menu → "Hapus".
2. Confirm → `deletedAt = .now`. **Soft delete only.**
3. The product vanishes from the catalogue and from scan lookup. Past `SaleLine` rows are untouched, because they snapshot name and price (R-04-3).

## 4. Rules & validations

| ID | Rule |
|---|---|
| R-03-1 | `barcode` is unique across all non-deleted products. Enforced in `ProductRepository`, **never** with `@Attribute(.unique)` — foundations §6, ADR-02. |
| R-03-2 | The uniqueness check runs **inside** `CatalogueService.create`, immediately before insert. A check performed only in the ViewModel is a defect. Violation → `barcodeAlreadyExists(productID:)`. |
| R-03-3 | `barcode` is nullable. Products with no barcode (`Gorengan`) are first-class: creatable, sellable, adjustable. Multiple products may have `nil`; nil is not a value and does not collide. |
| R-03-4 | `name` is required, trimmed, 1–80 characters. Empty or whitespace-only → `validationFailed(field: "name")`. Names are **not** unique — two suppliers' "Kopi Hitam" may legitimately coexist. |
| R-03-5 | `priceRp` is an `Int` > 0. Zero or negative → `validationFailed(field: "price")`. Free items are not a case this app supports. |
| R-03-6 | `stockQty` is a **cached** value, always equal to the sum of that product's movement deltas. It is only ever written by `StockService`. Any other assignment is a defect. |
| R-03-7 | `stockQty` may go **negative**. A negative quantity means goods left the shelf that the ledger did not know about — it is information, displayed in red, never clamped to zero. |
| R-03-8 | If a scanned code classifies as `.internalCode` (prefix `02` or `20`–`29`), warn before creating: *"Kode ini kode toko/timbangan, bukan barcode produk. Barcode-nya bisa berbeda tiap kemasan."* The operator may proceed. |
| R-03-9 | Every movement carries a `reason` from `StockReason`. A movement with no reason cannot be constructed. |
| R-03-10 | Movements are **immutable and never deleted**. A wrong movement is corrected by an offsetting `.adjustment`, never by editing or removing the original. |
| R-03-11 | Inserting a movement and updating `stockQty` happen in one `save()`. A movement without its cache update, or a cache update without its movement, is a data-integrity bug. |
| R-03-12 | Deletion is soft. `deletedAt != nil` excludes a product from every list and every lookup, including scan. It never removes it from a past sale. |
| R-03-14 | Any service call that **writes** to a product that is missing or soft-deleted throws `productNotFound`. Applies to `update`, `softDelete`, `record`, `adjust`, and `recompute` — a stale reference must fail loudly, not write to a dead row. "Missing" means `ProductRepository.find(id:)` does not return it. `movements(for:)` is exempt: it writes nothing, and §8 keeps a deleted product's movements "for audit", which is unreadable if the only reader refuses. |
| R-03-13 | `StockReason` is exactly: `opening`, `restock`, `sale`, `void`, `adjustment`. `sale` and `void` carry a non-nil `saleID`; the other three carry nil. |

## 5. Data model

### `Product`

| Field | Type | Null | Default | Notes |
|---|---|:--:|---|---|
| `id` | `UUID` | ✗ | `UUID()` | PK, app-generated |
| `name` | `String` | ✗ | `""` | 1–80 chars, trimmed, not unique |
| `priceRp` | `Int` | ✗ | `0` | rupiah, > 0 |
| `stockQty` | `Int` | ✗ | `0` | **cached**, = Σ movement deltas |
| `barcode` | `String?` | ✓ | `nil` | unique among non-deleted, repo-enforced. Trimmed on the way in; an empty or whitespace-only string is stored as `nil`, because a code is either present or absent and `""` is neither (R-03-3) |
| `supplierContactID` | `String?` | ✓ | `nil` | `CNContact.identifier` (02) |
| `supplierName` | `String?` | ✓ | `nil` | snapshot, paired with the above |
| `createdAt` | `Date` | ✗ | `Date()` | |
| `updatedAt` | `Date` | ✗ | `Date()` | touched on every field edit |
| `deletedAt` | `Date?` | ✓ | `nil` | soft delete |
| `movements` | `[StockMovement]?` | ✓ | `[]` | `.cascade`, inverse `\StockMovement.product` |

### `StockMovement`

| Field | Type | Null | Default | Notes |
|---|---|:--:|---|---|
| `id` | `UUID` | ✗ | `UUID()` | PK |
| `product` | `Product?` | ✓ | `nil` | inverse `\Product.movements` |
| `delta` | `Int` | ✗ | `0` | signed, never zero in practice |
| `reasonRaw` | `String` | ✗ | `"adjustment"` | backing for `StockReason`; String, not enum, for CloudKit safety |
| `note` | `String?` | ✓ | `nil` | operator text on `.adjustment` |
| `saleID` | `UUID?` | ✓ | `nil` | set iff reason is `.sale` or `.void` |
| `createdAt` | `Date` | ✗ | `Date()` | ledger order |

```swift
enum StockReason: String, CaseIterable {
    case opening, restock, sale, void, adjustment
}
```

**Indexes & constraints:** none declared. At 2,000 products (foundations §8) SwiftData's default fetch is fast enough. **No `@Attribute(.unique)` anywhere.**

## 6. States & transitions

**Product:** `active → deleted` (operator, soft). Terminal: `deleted`. There is no undelete in MVP; recreate by scanning the barcode again, which will now miss and open a fresh form.

**StockMovement:** no states. Immutable on insert (R-03-10).

## 7. Module contract

**Exports**

```swift
protocol CatalogueServicing {
    func create(name: String, priceRp: Int, barcode: String?,
                supplier: ContactRef?) throws -> Product
    func update(_ product: Product, name: String, priceRp: Int,
                supplier: ContactRef?) throws
    func softDelete(_ product: Product) throws
    func findBy(barcode: String) throws -> Product?    // excludes deleted
    func all() throws -> [Product]                     // excludes deleted, name-sorted
    func search(_ query: String) throws -> [Product]   // name contains, case-insensitive
}

protocol StockServicing {
    func record(product: Product, delta: Int,
                reason: StockReason, note: String?, saleID: UUID?) throws
    func adjust(product: Product, countedQty: Int, note: String) throws
    func recompute(product: Product) throws -> Int     // returns new qty
    func movements(for product: Product) throws -> [StockMovement]  // newest first
}
```

**Imports**

```
ScannerService.scan()      // 01 — get a barcode
BarcodeKind.of(_:)         // 01 — classify it for R-03-8
ContactService.pick()      // 02 — attach a supplier
```

**Internal only:** `ProductRepository`, `StockMovementRepository`, the `stockQty` cache update. Module 04 changes stock **only** through `StockServicing.record` — it may never write `stockQty` itself.

## 8. Edge cases

- **Scanned code already on a product.** Open that product. Never a duplicate, never an error dialog — the operator scanned a thing they own; showing them the thing is the correct answer.
- **Scanned code belongs to a soft-deleted product.** Treated as not found. A new product is created, and the old barcode now exists twice in the store — once on a deleted row. Correct: uniqueness is scoped to non-deleted rows (R-03-1).
- **Variable-weight barcode** (`20`/`02` prefix, price encoded in the digits). The operator gets the R-03-8 warning. If they proceed anyway, they will create a new product on every package — annoying, recoverable, and the warning is what prevents it.
- **Same physical product with two barcodes** (inner pack and box). Not supported. The operator creates two products, which is also how they price them. `[Later]`
- **Adjustment when counted equals current.** `delta == 0` → no movement written.
- **Negative stock.** Allowed and displayed in red (R-03-7). Do not clamp, do not block.
- **Delete a product with unsold stock.** Allowed. Movements survive on the deleted row for audit.
- **Delete a product that appears in past sales.** Allowed and harmless — `SaleLine` snapshots name and price, so history renders unchanged.
- **Price edited after the product has been sold.** Past `SaleLine` rows keep the old price (R-04-3). This is the single most important consequence of the snapshot rule.
- **Two rapid taps on Save.** ViewModel disables the button on first tap; the R-03-2 service check is the real guard.

## 9. Service surface

| Type | Method | Purpose | Errors |
|---|---|---|---|
| `CatalogueServicing` | `create` | New product | `validationFailed`, `barcodeAlreadyExists`, `persistenceFailed` |
| `CatalogueServicing` | `update` | Edit name/price/supplier | `validationFailed`, `productNotFound`, `persistenceFailed` |
| `CatalogueServicing` | `softDelete` | Hide from catalogue | `productNotFound`, `persistenceFailed` |
| `CatalogueServicing` | `findBy(barcode:)` | Scan lookup | `persistenceFailed` |
| `CatalogueServicing` | `all` / `search` | List and filter | `persistenceFailed` |
| `StockServicing` | `record` | Append a movement + update cache | `validationFailed`, `productNotFound`, `persistenceFailed` |
| `StockServicing` | `adjust` | Set to a counted quantity | `validationFailed`, `productNotFound`, `persistenceFailed` |
| `StockServicing` | `recompute` | Rebuild cache from ledger | `productNotFound`, `persistenceFailed` |
| `StockServicing` | `movements(for:)` | Read the ledger | `persistenceFailed` |

**Which `validationFailed` field.** §4 names the rules but not the field each
carries, so they are fixed here:

| Method | Condition | Field |
|---|---|---|
| `create` / `update` | name blank or over 80 chars (R-03-4) | `"name"` |
| `create` / `update` | `priceRp <= 0` (R-03-5) | `"price"` |
| `record` | `delta == 0` — §5 says never zero, and R-03-13 forbids a movement of zero | `"qty"` |
| `record` | `reason.requiresSaleID != (saleID != nil)` (R-03-13) | `"reason"` |
| `adjust` | `countedQty < 0` — nobody counts a negative number off a shelf | `"qty"` |
| `adjust` | `note` blank — a reasonless correction is unreadable a month later | `"reason"` |

Negative stock stays reachable through `record`, which is where a sale of goods
the ledger did not know about lands (R-03-7).

## 10. UI notes

**Produk (list)** — `Product` list, name-ascending, excludes deleted.
Row: name · `Rp.format(priceRp)` · `stockQty` badge, red when ≤ 0.
Top-right: a large **Scan** button. Search field filters by name; a blank
query is not a filter but the unfiltered list, which is what clearing the
field must show.
Empty state: *"Belum ada produk. Scan barcode untuk mulai."* with the scan button repeated.

**Product detail** — name, price, supplier via `ContactField`, current stock in large type,
red at or below zero to match the list badge. R-03-7 says *negative* is red and §10's badge
says *≤ 0*; taken literally that makes `0` red on one screen and not the other, so both use
`≤ 0` — which is also what D-05's "zero stock warns" asks for.
The `ContactField` here is an editor, not a label: picking or detaching a supplier writes
through `CatalogueServicing.update` immediately.
Primary action **Tambah Stok**. Secondary **Koreksi Stok**.
Below: movement history, newest first, each row `±delta · reason · date`, sign-coloured.
Menu: Edit · Hitung Ulang dari Riwayat · Hapus.

**New / edit product form** — barcode (shown, locked, or "Tanpa barcode"), name, price (number pad, `id_ID` formatted live), supplier `ContactField`.
The R-03-8 warning appears as a yellow inline banner above the fields, never as a blocking alert.

Formatting: money always via `Rp.format`. Dates as `d MMM, HH:mm` in `Asia/Jakarta`,
through `JakartaDay.shortDateTime(_:)` — one shared formatter, because a formatter that
forgets to set `timeZone` is the bug that helper exists to prevent.

Movement reasons render in Indonesian: `opening` "Stok awal", `restock` "Tambah stok",
`sale` "Penjualan", `void` "Pembatalan", `adjustment` "Koreksi". The raw values stay
English (R-03-13); only the labels are translated.

Recompute reports its result in an alert: matching → *"Stok cocok: 24."*, differing →
*"Stok tercatat 24, hasil hitung ulang 21. Angka sudah diperbaiki."* A difference is a cache
bug and is stated plainly, never smoothed over (§3).

## 11. Worked examples

```
STOCK LEDGER — Chitato Sapi Panggang 68g

  restock     +24    2026-08-21 08:05   supplier Toko Grosir Budi
  sale         -2    2026-08-21 10:12   saleID 20260821-001
  void         +2    2026-08-21 10:15   saleID 20260821-001
  adjustment   -3    2026-08-21 18:00   note "Kedaluwarsa"
  ────────────────────────────────────
  stockQty     21

  recompute() → 24 − 2 + 2 − 3 = 21. Cache correct.

ADJUSTMENT ARITHMETIC
  stockQty is 24, operator counts 21 on the shelf.
  delta = 21 − 24 = −3  → movement(−3, .adjustment, note "Kedaluwarsa")
  stockQty becomes 21.

  Operator counts 21 again the next day, nothing changed.
  delta = 21 − 21 = 0   → NO movement written. Ledger stays clean.

BARCODE COLLISION
  create(name: "Chitato Sapi Panggang 68g", barcode: "8992775311011")  → OK
  create(name: "Chitato Rasa Keju 68g",     barcode: "8992775311011")
    → throws barcodeAlreadyExists(productID: <the Sapi Panggang product>)
    → UI: "Barcode ini sudah dipakai Chitato Sapi Panggang 68g." + Lihat
    → the name comes from the §7 all() export, not a new lookup method;
      "Lihat" replaces the form on the stack with that product's detail.

BARCODE-LESS PRODUCT
  create(name: "Gorengan", priceRp: 2000, barcode: nil)  → OK
  create(name: "Es Teh",   priceRp: 3000, barcode: nil)  → OK
  Two nil barcodes do not collide. nil is not a value.
```

## 12. Acceptance criteria

| ID | Criterion |
|---|---|
| AC-03-1 | Scanning a barcode already on a product opens that product and creates nothing. |
| AC-03-2 | Scanning an unknown barcode opens the new-product form with the barcode prefilled and non-editable. |
| AC-03-3 | `create` with a barcode already in use throws `barcodeAlreadyExists` carrying the existing product's ID. |
| AC-03-4 | Two products with `barcode == nil` can both be created and both appear in the list. |
| AC-03-5 | `create` with an empty or whitespace-only name throws `validationFailed(field: "name")`. |
| AC-03-6 | `create` with `priceRp <= 0` throws `validationFailed(field: "price")`. |
| AC-03-7 | Scanning `2011234501234` shows the R-03-8 warning, and proceeding still creates the product. |
| AC-03-8 | Add stock 24 on a product at 0 produces exactly one `.restock` movement of `+24` and `stockQty == 24`. |
| AC-03-9 | Adjusting to a counted quantity equal to current stock writes no movement. |
| AC-03-10 | After the §11 ledger sequence, `stockQty == 21` and `recompute()` also returns 21. |
| AC-03-11 | `stockQty` can reach a negative value; it is not clamped. |
| AC-03-12 | A soft-deleted product is absent from `all()`, from `search()`, and from `findBy(barcode:)`. |
| AC-03-13 | Editing a product's price leaves every existing `SaleLine.unitPriceRp` unchanged. |
| AC-03-14 | Project-wide, `stockQty` is assigned only inside `StockService`. |
| AC-03-15 | No `@Attribute(.unique)` appears in `Product` or `StockMovement`. |
| AC-03-16 | `StockService.record` against a soft-deleted product throws `productNotFound` and writes no movement. |

## 13. Build checklist

1. `Product` + `StockMovement` models, CloudKit rules verified against foundations §6
2. `ProductRepository`, `StockMovementRepository`
3. `StockService` — `record`, `adjust`, `recompute`, the atomic cache update (R-03-11)
4. `CatalogueService` — CRUD with R-03-1..5 validation
5. Product list + search + scan entry point
6. Product detail + movement history
7. New/edit form with the R-03-8 warning banner
8. Add-stock and adjust-stock sheets
9. Tests for every `R-03-*` and `AC-03-*`, against in-memory containers

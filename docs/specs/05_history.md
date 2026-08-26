# 05 · History & Summary  [MVP]

> Build order #5 · Est. 0.5 session
> Depends on: 03 catalogue, 04 sale · Consumed by: nothing
> Code location: `Features/History/`

---

## 1. Purpose & scope

Read-only views over sales: a chronological list, a sale detail screen, and a daily summary. Owns **no entities** — every number here is derived from `Sale` and `SaleLine`, which module 04 owns.

The one write this module can trigger is a void, and even that is delegated: it calls `SaleServicing.void` and owns none of the logic.

**Non-goals**

- Owns no tables, defines no models, holds no business rules.
- No charts, no trends, no week/month comparisons. `[Later]`
- No CSV or PDF export. `[Later]`
- No profit or margin — there is no cost price in this system.
- No stock valuation report.
- No custom date-range picker. Today, yesterday, and an all-time list.
- Does **not** implement void; it presents it (module 04, R-04-12..15).

## 2. Roles & permissions

Single operator. Everything visible.

## 3. Flows

**Review today (Operator)**
1. Riwayat tab opens on **today**, Asia/Jakarta.
2. Summary card at the top: total, sale count, cash vs QRIS split.
3. Below: today's sales, newest first. Voided sales appear struck through and excluded from every total.

**Inspect a sale (Operator)**
1. Tap a row → sale detail: number, timestamp, lines with snapshotted names and prices, total, payment method, change (cash only), customer if attached.
2. If voided: a banner with `voidedAt` and `voidReason`, and no void action.

**Void from history (Operator)**
1. Sale detail → **Batalkan** → module 04's void sheet.
2. On success, the list and summary refresh in place. The screen does not navigate away.

**Browse all history (Operator)**
1. Segmented control: `Hari Ini | Kemarin | Semua`.
2. `Semua` lists every sale newest-first, grouped by Jakarta day with a per-day subtotal header.

## 4. Rules & validations

| ID | Rule |
|---|---|
| R-05-1 | Every "day" boundary is **Asia/Jakarta**, not UTC and not the device locale (foundations §6). A sale at 08:00 WIB belongs to that WIB day. |
| R-05-2 | Voided sales are **excluded** from `totalRp`, from the sale count, and from the cash/QRIS split — but are **always still listed**, struck through. Hiding them would make the ledger a lie. |
| R-05-3 | Every displayed figure is derived at read time from stored `Sale.totalRp` values. This module stores no aggregate and caches nothing. |
| R-05-4 | Sale detail renders `SaleLine.nameSnapshot` and `unitPriceRp` — **never** a live lookup on `Product`. History shows what was sold at the price it was sold for. |
| R-05-5 | The cash/QRIS split sums `Sale.totalRp` grouped by `paymentMethodRaw`, over completed sales only. Cash total + QRIS total == day total, always. |
| R-05-6 | Sales sort by `createdAt` descending everywhere. Never by `number` — a string sort is only accidentally correct. |
| R-05-7 | A summary over an empty day shows `Rp 0` and `0 transaksi`. It is never blank and never an error. |
| R-05-8 | This module contains no `save()` call and no `ModelContext` write. Grep is the test. |

## 5. Data model

**None.** This module owns no entity (foundations §4). It defines read-only view structs:

```swift
struct DaySummary: Equatable {
    let day: Date          // Jakarta midnight
    let totalRp: Int       // completed only
    let saleCount: Int     // completed only
    let cashRp: Int
    let qrisRp: Int
    let voidedCount: Int   // shown as context, excluded from totals
}
```

## 6. States & transitions

None.

## 7. Module contract

**Exports:** none. Nothing consumes this module.

**Imports**

```
SaleService.sales(onJakartaDay:)      // 04
SaleService.allSales(limit:offset:)   // 04
SaleService.void(_:reason:)           // 04 — presented, not implemented
Rp.format(_:)                         // 01
```

**Internal only:** `DaySummary` computation, day grouping.

## 8. Edge cases

- **Empty day.** `Rp 0`, `0 transaksi`, empty-list message. Not an error (R-05-7).
- **Every sale of the day voided.** Total `Rp 0`, count `0`, and the voided sales still listed with a "3 dibatalkan" note.
- **Sale whose product was deleted.** Renders from snapshots (R-05-4). Nothing is missing.
- **Sale with a customer whose contact was deleted.** Renders `customerName` snapshot (module 02, R-02-2).
- **Void from the detail screen while the list is behind it.** Both refresh; the detail stays open and switches to its voided presentation.
- **A sale created at 00:00:30 WIB.** Belongs to the new Jakarta day. Verify by comparing against the device's own timezone if it is not WIB — the grouping must not change.
- **Device timezone is not Asia/Jakarta** (owner travelling, or a simulator on UTC). Grouping stays WIB. R-05-1 is absolute.
- **18,000 sales after a year.** `Semua` loads with `limit: 100, offset:` and appends on scroll. This is the one place in the app where paging exists, and only because the list is genuinely unbounded.

## 9. Service surface

None exported. Consumes module 04's surface only.

## 10. UI notes

**Riwayat (list)**

| Region | Content |
|---|---|
| Segmented control | `Hari Ini · Kemarin · Semua` |
| Summary card | Total in large type. Below: `N transaksi` · `Tunai Rp x` · `QRIS Rp y`. If any voids: `N dibatalkan` in secondary colour. |
| List row | `number` · time `HH:mm` · payment icon (`banknote` / `qrcode`) · `totalRp` right-aligned. Voided: struck through, secondary colour. |
| Grouping (`Semua` only) | Section header per Jakarta day with the day's subtotal |
| Empty | "Belum ada transaksi hari ini" |

**Sale detail** — number and full timestamp at the top; lines as `name · qty × unitPrice · lineTotal`; total; payment method; cash received and change for cash sales only; customer if present. Voided sales get a destructive-tinted banner with reason and time, and no void button.

Formatting: money through `Rp.format`. Times as `HH:mm`, dates as `d MMM yyyy`, both `Asia/Jakarta`, `id_ID`.

## 11. Worked examples

```
DAY SUMMARY — 21 Aug 2026, Asia/Jakarta

  20260821-001   10:12   Tunai   29.000
  20260821-002   11:40   QRIS    12.000
  20260821-003   14:05   Tunai    8.000   ← VOIDED, reason "salah barang"
  20260821-004   16:22   QRIS     5.000

  Total       46.000     (29.000 + 12.000 + 5.000 — void excluded)
  Transaksi   3          (4 rows listed, 1 voided)
  Tunai       29.000
  QRIS        17.000     (12.000 + 5.000)
  Check       29.000 + 17.000 == 46.000  ✓   (R-05-5)
  Dibatalkan  1

EMPTY DAY — 22 Aug 2026
  Total Rp 0 · 0 transaksi · Tunai Rp 0 · QRIS Rp 0
  List: "Belum ada transaksi hari ini"

DAY BOUNDARY
  Sale at 2026-08-21 23:58 WIB  → 21 Aug group
  Sale at 2026-08-22 00:03 WIB  → 22 Aug group
  In UTC these are 16:58 and 17:03 on 21 Aug — the same UTC day.
  Grouping on UTC would put them together. It must not.

DELETED PRODUCT
  Sale 20260821-001 sold "Chitato Sapi Panggang 68g" at 12.000.
  The product is deleted and a new one created at 15.000.
  Sale detail still shows "Chitato Sapi Panggang 68g · 2 × 12.000 = 24.000".
```

## 12. Acceptance criteria

| ID | Criterion |
|---|---|
| AC-05-1 | The §11 day produces total 46.000, count 3, cash 29.000, QRIS 17.000. |
| AC-05-2 | The voided sale appears in the list, struck through, and in no total. |
| AC-05-3 | Cash total + QRIS total equals the day total for any dataset. |
| AC-05-4 | A day with no sales shows `Rp 0` and `0 transaksi` without error. |
| AC-05-5 | With the device timezone set to UTC, the §11 boundary sales still group into 21 and 22 August WIB respectively. |
| AC-05-6 | Sale detail for a sale whose product was deleted renders the snapshotted name and price. |
| AC-05-7 | Voiding from sale detail updates the list and summary without navigating away. |
| AC-05-8 | Sales are ordered by `createdAt` descending, verified with two sales whose numbers and timestamps disagree in order. |
| AC-05-9 | `Features/History/` contains no `save()`, no `insert(`, and no `ModelContext` write. |

## 13. Build checklist

1. `DaySummary` + the aggregation function — build and test this **before** any view
2. Jakarta-day boundary helper, tested against a UTC device timezone
3. History list with the segmented control
4. Summary card
5. Sale detail, including the voided presentation
6. Void entry point wired to module 04
7. `Semua` grouping + paging
8. Tests for every `R-05-*` and `AC-05-*`

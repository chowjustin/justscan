# Decision Log

Append-only. Never edit a locked row — supersede it with a new one and note the reversal.

## Locked

| # | Decision | Rationale | Date | Affects |
|---|---|---|---|---|
| D-01 | Single operator, no auth, no roles | Owner and cashier are the same person. Accepted consequence: no fraud controls. | 2026-08-21 | all |
| D-02 | Stock tracked; auto-decrement on sale; manual add from product detail | Owner needs to know what is on the shelf, but not a purchasing workflow | 2026-08-21 | 03, 04 |
| D-03 | Local-only now, iCloud later | One device today. **Forces the CloudKit schema rules from day one** — this is not a deferrable decision. | 2026-08-21 | all, esp. 03, 04 |
| D-04 | Stock is an append-only `StockMovement` ledger; `stockQty` is a cache | A bare counter cannot answer "why is my stock wrong". D-06 already required reversal semantics on the money side; stock must match or neither is trustworthy. | 2026-08-21 | 03, 04 |
| D-05 | Zero stock warns, never blocks the sale | A shop that cannot sell what is in the customer's hand is broken. Negative stock is information, not an error. | 2026-08-21 | 03, 04 |
| D-06 | Void writes a reversal record; sales are never deleted or edited | Audit trail. Money and stock reverse together (R-04-13). | 2026-08-21 | 04, 05 |
| D-07 | Payment method Cash or QRIS, one per sale | Matches how these shops already take money | 2026-08-21 | 04 |
| D-08 | QRIS is record-only — static QR, manual confirmation, no gateway | Zero integration cost; matches existing behaviour. `cashReceivedRp` and `changeRp` are nil, never 0. | 2026-08-21 | 04 |
| D-09 | Money is `Int` rupiah. No `Decimal`, no floats. | IDR has no circulating subunit, so `Int` is exact with no scaling factor | 2026-08-21 | all |
| D-10 | Barcode uniqueness enforced in the repository, not the schema | CloudKit does not support unique constraints, and D-03 makes CloudKit a stated future requirement (ADR-02) | 2026-08-21 | 03 |
| D-11 | Contacts stored as identifier **plus** name snapshot | `CNContact.identifier` breaks on delete and merge. A deleted contact must degrade to a readable name, never a blank. | 2026-08-21 | 02, 03, 04 |
| D-12 | MVVM + `@Observable`; no `@Query` in views; no TCA | Services stay testable without a UI, and no third-party framework competes with learning Swift itself (ADR-03) | 2026-08-21 | all |
| D-13 | SwiftData over Core Data and GRDB | Least code for a greenfield iOS 17+ app; the repository layer keeps the swap open if reporting outgrows it (ADR-01) | 2026-08-21 | all |
| D-14 | The cart is in-memory only; nothing persists before tender | Tender is the pivot event. A crash mid-cart losing the cart is acceptable; a half-written sale is not. | 2026-08-21 | 04 |
| D-15 | `SaleLine` snapshots name and price; `productID` is a weak `UUID?`, not a relationship | A product edit or deletion must be structurally incapable of altering financial history | 2026-08-21 | 03, 04, 05 |
| D-16 | All day boundaries are Asia/Jakarta | Grouping on UTC splits a trading day in half | 2026-08-21 | 04, 05 |
| D-17 | Sale numbers are `{YYYYMMDD}-{NNN}`, no gaps, no reuse; voided sales keep their number | A gap in a receipt sequence is indistinguishable from a hidden sale | 2026-08-21 | 04 |

## Deferred (Later)

| Item | Why deferred | Bring back when |
|---|---|---|
| iCloud backup / sync | One device. Schema already compatible. | Second device, or the owner asks for backup |
| Staff accounts & roles | One operator. A full module, not a small change. | A second person is employed |
| Receipt printing | Verbal totals work at this size | Customers ask, or tax requires it |
| Shift open/close, Z-report | Only meaningful with staff to hold accountable | Staff exist |
| Discounts | Owner discounts mentally | Owner asks twice |
| PPN / tax lines | Below the registration threshold | Business registers for PPN |
| Partial refund of single lines | Whole-sale void covers every case seen | A real partial return happens |
| Held / parked sales | One cart at a time is enough at this volume | Two customers regularly overlap at the counter |
| Product photos & categories | 200 products is scrollable and name-searchable | Catalogue passes ~300 products |
| QRIS gateway integration | Manual confirmation matches existing behaviour | Manual confirmation becomes the bottleneck |
| Multi-barcode per product | One code covers packaged goods | Owner stocks inner-pack and box of the same item |
| Charts, trends, CSV export | Daily totals answer the question being asked | The owner asks a question a number cannot answer |
| Cart preservation when adding a product mid-sale | Adds a navigation state machine for a rare case | It happens often enough to complain about |

## Open

| ID | Question | Blocking | Asked |
|---|---|---|---|
| — | none | — | — |

Interview closed with no open questions. Any `⚠️ OPEN` marker that appears in a spec during the build must be mirrored here before work continues.

## Reversed

| Date | Reversal |
|---|---|
| 2026-08-21 | Dropped `@Attribute(.unique) var barcode` from the module 03 draft. It works locally and fails **silently** the day CloudKit is enabled (D-03). Superseded by D-10. |
| 2026-08-21 | Dropped the bare `stockQty` counter. A void (D-06) would have moved stock with no record, contradicting the audit trail the same decision demanded. Superseded by D-04. |

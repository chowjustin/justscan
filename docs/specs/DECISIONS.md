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
| D-18 | CloudKit is enabled from session 1, not at the end | An incompatible schema still compiles; the failure only arrives when a CloudKit-backed store loads (`NSCocoaErrorDomain 134060`). Enabling it on day one makes every launch a schema validation. Supersedes the "capability stays off" line in 01 §1. | 2026-08-28 | 01, all |

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
| 2026-08-28 | `04 §3`'s tender and void steps, which called `StockService.record` per line. `record` commits itself (R-03-11), so N lines would be N saves and a failure on line two would leave line one's movement written — the exact partial write R-04-15 and AC-04-16 exist to forbid. Superseded by `StockServicing.stage`: `record` without the commit, stamped with a caller-supplied instant, committed once by the caller. `record` keeps its signature and its behaviour. |
| 2026-08-28 | `03 §4`'s R-03-14 again, on its soft-deleted half. It made every writer refuse a deleted product, while `04 §8` states twice that a sale of goods deleted mid-cart, and the void reversing it, must land on that product's ledger — "correct and harmless". `stage` now refuses a **missing** product and accepts a **soft-deleted** one; the four catalogue-facing writers are unchanged. |
| 2026-08-28 | `04 §8`'s "Crash between insert and save. SwiftData rolls back." True of a crash, false of a *caught* save error: the inserts stay in the shared context and ride along on the next successful save, so a retried tender would commit the failed attempt too. `ProductRepository.rollback()` added beside `save()`, for the same one-place reason, called only on a failed commit. |
| 2026-08-28 | `04 §8`'s "Taking it navigates away", which named no destination while `04 §1` says the screen never leaves itself and `04 §7` imports nothing from `Features/Catalogue/`. Resolved as a push onto the Jual tab's **own** stack rather than a tab switch, which would have put cross-tab navigation state into module 01's `RootTabView`. |
| 2026-08-28 | `03 §4`'s R-03-14, which said "every `StockService` method" throws `productNotFound` for a soft-deleted product. Its own reason is *"must not write to a dead row"*, and §8 keeps a deleted product's movements "for audit" — unreadable if the only reader refuses. Narrowed to the five methods that write; `movements(for:)` stays legible. |
| 2026-08-28 | `03 §9`'s error table, which omitted `productNotFound` from `update`, `softDelete`, and every `StockServicing` row while §4's R-03-14 demanded it, and named no field for any `validationFailed`. The table now matches the rules and fixes the six field values. |
| 2026-08-28 | `03 §10`'s two stock colours. The list badge said "red when ≤ 0" and R-03-7 said "negative in red", which taken literally paints `0` red on the list and not on the detail screen. Both now use `≤ 0`, matching D-05's "zero stock warns". |
| 2026-08-28 | `02 §7`'s `authorizationStatus: CNAuthorizationStatus`. Naming a Contacts type in the export forces `import Contacts` on every caller *and every conformance* — the test fake included — which makes AC-02-7 unsatisfiable by construction, and defeats the reason the module exists. Replaced by `ContactAccess`, owned by `Core/Contacts/`. |
| 2026-08-28 | `02 §3`'s "Found → open the contact card". Presenting `CNContactViewController` requires `descriptorForRequiredKeys()` — phone numbers, emails, postal addresses — which R-02-6 forbids and §1 lists as a non-goal. §10's Filled state defined no tap action either. Changing a supplier is detach-then-pick. |
| 2026-08-28 | `STRUCTURE.md`'s `ContactPickerView.swift` as a `UIViewControllerRepresentable`, for the same reason `DataScannerView` was reversed in session 1: the export is `pick() async -> ContactRef?`. Replaced by `ContactPickerPresenter.swift`. |
| 2026-08-28 | `01 §1`'s "no persistence models" non-goal. It could not survive its own §5, which names all four `@Model` types in the `Schema`, nor AC-01-6 and AC-01-8, which insert and seed them. Session 1 now declares the four types as **storage only** — zero behaviour, every rule still owned by 03 and 04. |
| 2026-08-28 | `01 §1`'s "the capability stays off". Contradicted by `CLOUDKIT_CHECKLIST.md` Part 4 and by the repo's own entitlements, which already declared `iCloud.chow.JustScan`. Superseded by D-18: CloudKit on from session 1, with R-01-9's local-only fallback so it can never stop the shop trading. |
| 2026-08-28 | `STRUCTURE.md`'s `DataScannerView.swift` as a `UIViewControllerRepresentable`. The exported contract is `scan() async throws -> String?`, which a representable cannot satisfy without moving scanner lifetime into the view. Replaced by `BarcodeScanPresenter.swift`. |
| 2026-08-21 | Dropped `@Attribute(.unique) var barcode` from the module 03 draft. It works locally and fails **silently** the day CloudKit is enabled (D-03). Superseded by D-10. |
| 2026-08-21 | Dropped the bare `stockQty` counter. A void (D-06) would have moved stock with no record, contradicting the audit trail the same decision demanded. Superseded by D-04. |

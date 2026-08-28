# Build Progress

Read this file **first** at the start of every session. Update it at the end of every session, before committing.

## Current

- **Active module:** 04 Sale — **done, 18/18**
- **Session goal:** 04 Sale ✅
- **Next up:** 05 History

## Status

| Module | Status | Acceptance criteria passing | Notes |
|---|---|---|---|
| 01 App shell | **done** | **8/8** | 52 tests, 125 expectations, all passing. CloudKit mirroring verified live. |
| 02 Contact link | **done** | **8/8** | 31 new tests, 83 passing overall. Ships no screens — one shared `ContactField` that 03 and 04 embed. |
| 03 Catalogue | **done** | **16/16** | 57 new tests, 140 passing overall. `StockService` is the only writer of `stockQty`. |
| 04 Sale | **done** | **18/18** | 66 new tests, 206 passing overall. `SaleService` never touches `stockQty`; movements are *staged* so the whole tender is one `save()`. |
| 05 History | todo | 0/9 | Read-only |

**Total: 50/59 acceptance criteria.**

## Session order and sizing

| Session | Module | Watch for |
|---|---|---|
| 1 | 01 App shell | Patterns set here are copied four more times. Do not rush the repository protocols. |
| 2 | 02 Contact link | Small. If it finishes early, do **not** start 03 — write its tests instead. |
| 3 | 03 Catalogue | Build `StockService` before any view. R-03-11 atomicity is the hard part. |
| 4 | 04 Sale | Write AC-04-16 (no partial write) **first**, before the commit path exists. |
| 5 | 05 History | Build `DaySummary` before any view. The Jakarta-day helper already exists; `VoidSheet` already exists too — 05 presents it and implements none of it. |

Budget the remaining days for polish, the three ADRs, and the golden path run — not for more modules.

## Deviations from spec

| Module | What changed | Why | Spec updated? |
|---|---|---|---|
| 01 | The four `@Model` types are declared in session 1, not 3 and 4 | 01 §5's `Schema` names all four, and AC-01-6 / AC-01-8 insert and seed them. The non-goal could not survive its own §5. They are **storage only** — zero behaviour; 03 and 04 still own every rule, and add them without touching the fields. | Yes — 01 §1 and §5 rewritten, reversal logged in `DECISIONS.md` |
| 01 | CloudKit is **on**, with a local-only fallback | `CLOUDKIT_CHECKLIST.md` Part 4 cited `D-18` and `R-01-9`, neither of which existed, while the repo's entitlements already declared `iCloud.chow.JustScan`. Three sources disagreed. | Yes — **D-18** added to `DECISIONS.md`, **R-01-9** added to 01 §4, 01 §1 non-goal rewritten |
| 01 | `Info.plist` gained `UIBackgroundModes: remote-notification` | Required by `CLOUDKIT_CHECKLIST.md` Part 2, and its absence made CloudKit log `BUG IN CLIENT OF CLOUDKIT` on every launch. Found by running the app, not by reading it. | No spec change needed — the checklist already required it |
| 01 | `DataScannerView.swift` → `BarcodeScanPresenter.swift` | The export is `scan() async throws -> String?`, a value a ViewModel awaits. A `UIViewControllerRepresentable` would put scanner lifetime and results in the view, inverting the layering rule. | Yes — `STRUCTURE.md` updated, reversal logged |
| 01 | `save()` lives on `ProductRepository` alone | Both repositories share one `ModelContext`, so one call commits a whole operation. Putting it in one place makes "one `save()` per business operation" structural instead of a rule to remember (R-03-11, R-04-15). | No — no spec states the repository method sets |
| 01 | Seed suppliers use a synthetic identifier | Operator's call over the recommendation. Both D-11 columns are populated, at the cost of `ContactService.resolve(id:)` returning nil for `"seed-toko-grosir-budi"` permanently. **Module 02 must not treat an unresolvable identifier as an error.** | Yes — foundations §9 records the consequence |
| 01 | AC-01-2 said "five strings"; §11 lists four | Off-by-one in the spec. Found by writing the test against §11. | Yes — AC-01-2 now says four |

| 02 | `authorizationStatus` returns `ContactAccess`, not `CNAuthorizationStatus` | Naming a Contacts type in the §7 export forces `import Contacts` on every caller **and every conformance** — including `FakeContactService` — which makes AC-02-7 unsatisfiable by construction, and defeats the one thing this module is for. `Core/Contacts/` is now the only folder in the app or the tests that imports the framework. | Yes — 02 §5, §7 and §9 rewritten, reversal logged in `DECISIONS.md` |
| 02 | No "open the contact card" | 02 §3 step 3 asked for it; `CNContactViewController.descriptorForRequiredKeys()` fetches phone numbers, emails, and postal addresses, which R-02-6 forbids and §1 lists as a non-goal. §7 exported nothing for it and §10's Filled state defined no tap action — three sections disagreed, and the privacy rule wins. Changing a supplier is detach-then-pick. | Yes — 02 §3 rewritten, reversal logged |
| 02 | `ContactPickerView.swift` → `ContactPickerPresenter.swift` | Same reasoning as session 1's `BarcodeScanPresenter`: the export is `pick() async -> ContactRef?`, a value a ViewModel awaits. A representable would put picker lifetime in the view. | Yes — `STRUCTURE.md` updated, reversal logged |
| 02 | `ContactField` resolves **only when access is already granted** | The spec required a "contact gone" state without saying what triggers it. Resolving on appear would make opening a product detail screen raise the app's only Contacts prompt — the picker raises none — at the moment it is least explicable. Without access the name renders normally rather than being marked gone, because "gone" would be a guess. | Yes — 02 §3 gained steps 2 and 5 |
| 02 | The detach control stays in the "contact gone" state | §10 said "tapping does nothing", which read literally leaves a product whose supplier was deleted permanently unable to have its supplier changed. The row is still not tappable; the `xmark` is a separate control. | Yes — 02 §10 row rewritten |
| 02 | 02 added paired `supplier` / `customer` accessors to `Product` and `Sale` | `STRUCTURE.md` already specified both, and they are where R-02-5 stops being a rule someone remembers and starts being unrepresentable state. Trivial computed properties, which `CONVENTIONS.md` permits on a model; 03 and 04 still own every rule about those entities. | No — `STRUCTURE.md` already said so |
| 02 | `ContactFieldViewModel.swift` is a sixth file in `Core/Contacts/` | A View may not call a Service, and the three states of §10 are a decision, not a rendering. `STRUCTURE.md` listed four files and no ViewModel. | Yes — `STRUCTURE.md` updated |

| 03 | R-03-14 narrowed to the five methods that **write** | It said "every `StockService` method", but its own stated reason is *"must not write to a dead row"*, and §8 promises a deleted product's movements survive "for audit" — which is unreadable if the only reader throws. `movements(for:)` is now exempt; the five writers are not. | Yes — R-03-14 rewritten, reversal logged in `DECISIONS.md` |
| 03 | §9's error table was incomplete against §4 | It omitted `productNotFound` from `update`, `softDelete`, and every `StockServicing` row while R-03-14 demanded it, and named no `field` for any `validationFailed`. Two sections disagreed about what a method throws. | Yes — §9 now carries the missing errors plus a six-row field table |
| 03 | `record` rejects `delta == 0`; `adjust` rejects a negative count and a blank note | §9 lists `validationFailed` for both methods and §4 never names a trigger, so the errors were unreachable as specced. §5 says delta is "never zero in practice" and R-03-13 forbids a movement of zero — that is the trigger. | Yes — §9's field table records all six |
| 03 | `ProductRepository.find(id:)` added | R-03-14's "missing" half had no detection mechanism: soft delete means rows are never removed, so `deletedAt` catches deleted rows and nothing catches a `Product` that was never inserted. Internal to the module — not a §7 export. | Yes — `STRUCTURE.md` updated |
| 03 | The detail screen's stock is red at `≤ 0`, not `< 0` | §10's list badge said "≤ 0" and R-03-7 said "negative"; following both literally paints `0` red on one screen and not the other. D-05's "zero stock warns" settles it. | Yes — 03 §10 rewritten, reversal logged |
| 03 | An empty-string barcode is stored as `nil` | Spec silent. `""` is neither a code nor absence, and left as a value it would collide with itself on the second barcode-less product — the exact case R-03-3 exists to allow. | Yes — 03 §5 records it |
| 03 | A blank `search()` query returns `all()` | Spec silent. Clearing the search field must show the catalogue, not an empty screen. | Yes — 03 §10 records it |
| 03 | `JakartaDay.shortDateTime(_:)` added — a module 01 file | §10 requires `d MMM, HH:mm` in Asia/Jakarta and no formatter existed. The alternative is each feature building its own, and a formatter that forgets `timeZone` is the exact bug `JakartaDay` exists to prevent. 05 needs the same string. | Yes — `STRUCTURE.md` updated |
| 03 | `StockReason` gained `requiresSaleID` and a Indonesian `label` | The first is R-03-13 turned from a sentence into something `record` can enforce. The second is five operator-facing strings no spec provided; they live in `StockMovementRow.swift`, next to the only thing that renders them. | Yes — 03 §10 records the five labels |
| 03 | `SeedService` still sets `stockQty` through `Product.init` | AC-03-14 says `stockQty` is assigned only inside `StockService`. The DEBUG seed sets it via the initialiser and writes the matching `.opening` movement in the same `save()`, so the cache is never wrong. Rewriting a module 01 file to route four DEBUG rows through `record` would turn one `save()` into four for no gain. The grep gate targets mutation (`stockQty =`), which the initialiser is not. | No — recorded as a written exemption below |
| 03 | `ContactField` on the product detail screen persists immediately | §10 puts the supplier "via `ContactField`" on a screen with no Save button. The field is an editor by construction — it has a picker and a detach control — so a change there writes through `CatalogueServicing.update`. The alternative was a decorative row that silently discards what the operator did. | Yes — 03 §10 rewritten |
| 03 | `CatalogueViewModelTests.swift` added | AC-03-1, AC-03-2, and AC-03-7 are ViewModel decisions, and `STRUCTURE.md` listed no ViewModel test file for 03. Views themselves are still never tested. | Yes — `STRUCTURE.md` updated |

| 04 | `StockServicing` gained `stage(product:delta:reason:note:saleID:at:)` | `record` commits itself (R-03-11), so `complete` calling it per line would be N saves, and a failure on line two would leave line one's movement written — the exact partial write R-04-15 and AC-04-16 forbid. `stage` is `record` without the commit; the caller commits once. The `at:` parameter is CONVENTIONS.md §Time made enforceable: one instant for the number, the sale, and every movement. `record` is unchanged and is still what 03 uses. | Yes — 03 §7 and §9 rewritten, 04 §3 and §4 rewritten, reversal logged in `DECISIONS.md` |
| 04 | `stage` accepts a **soft-deleted** product; the four catalogue-facing writers still refuse one | 04 §8 states twice that a sale of goods deleted mid-cart, and the void reversing it, land on that product's ledger — "correct and harmless" — while R-03-14 forbade exactly that. Two specs disagreed and the one describing the money case wins. A **missing** row is still refused: money must never move with no stock behind it. | Yes — R-03-14 rewritten with both exemptions named, reversal logged |
| 04 | `ProductRepository` gained `findAny(id:)` | `DraftLine` carries a `UUID`; `StockServicing` takes a `Product`. Nothing in either §7 mapped one to the other, and `find(id:)` filters out the deleted rows the row above says we need. It is the one read in the app that deliberately sees dead rows. | Yes — `STRUCTURE.md` updated, 04 §7 imports updated |
| 04 | `ProductRepository` gained `rollback()` | 04 §8 says "Crash between insert and save. SwiftData rolls back" — true of a crash, false of a *caught* save error, where the inserts stay in the shared context and ride along on the next successful save. A retried tender would then commit the failed attempt too. Pinned by `test_AC0416_rollbackLeavesNothingToRideAlong`. | Yes — reversal logged; lives beside `save()` for the same one-place reason |
| 04 | `complete` and `void` can throw `productNotFound` | §9's table listed neither, but a `productID` that resolves to no row leaves money moving with no stock behind it — the same "together or neither" R-04-13 states for the void. Unreachable from the cart, which is built from `findBy(barcode:)`. | Yes — 04 §9 gained the error and a three-row condition table |
| 04 | `complete` **throws** on a line at `qty < 1` rather than skipping it | The open question left from session 3 suggested skipping. R-04-16 makes the cart remove such a line, so a zero-qty draft can only be hand-built, and §9 already lists `validationFailed` for `complete` with no other trigger. Silently dropping a line the operator can see on screen is worse than refusing the tender. | Yes — 04 §9 records it |
| 04 | Cash with `cashReceivedRp == nil` is `insufficientCash(shortfallRp: totalRp)`; QRIS **discards** a non-nil cash amount | Spec silent on both. No cash entered is not a free sale. And R-04-10 is about what is *stored*, so storing a number that means nothing is the failure it names — discarding it is the rule, not a violation of it. | Yes — 04 §9 records both |
| 04 | "Tambah Produk Baru" pushes `ProductFormView` onto the **Jual tab's own** stack | §8 said "navigates away" and named no destination; §1 says the screen never leaves itself and §7 imports nothing from `Features/Catalogue/`. A tab switch would put cross-tab navigation state into module 01's `RootTabView`. The cart is discarded on the way and the banner says so, which §8 requires. | Yes — 04 §8 rewritten, reversal logged |
| 04 | The customer `ContactField` lives on the **cart** screen | Three sources disagreed: §3.9 puts it in the ring-up flow, §10's layout table listed no row for it, and `ContactFieldViewModel`'s own comment said `TenderViewModel` holds it. §3 is the only one that actually places it, so `CartViewModel` owns it. It clears on a successful tender — the next customer is a different customer. | Yes — 04 §10 gained a Customer row |
| 04 | Stock for the R-04-6 warning lives in a `[UUID: Int]` on `CartViewModel`, not on `DraftLine` | §7 pins `DraftLine` character for character, and a line is a price and a quantity quoted to a customer — stock is neither. Captured at scan time, which is what the operator saw. | No — §7 already fixed the struct |
| 04 | `TenderViewModelTests.swift` added | `STRUCTURE.md` listed no ViewModel test file for the tender sheet, but the shortfall, the change, and `canConfirm` are decisions, and a View may not make them. Same precedent as session 3's `CatalogueViewModelTests`. | Yes — `STRUCTURE.md` updated |
| 04 | `FailingSaveProductRepository.swift` added to `Support/` | `InMemoryProductRepository` has no store behind it, so it can prove the error and the save count but not AC-04-16's "zero sales, zero lines, zero movements". This decorator keeps every read and insert on a real `ModelContext` and fails only the save, so a second context can be asked what landed. | Yes — `STRUCTURE.md` updated |
| 04 | `DraftLine` conforms to `Identifiable` in an extension inside `CartView.swift` | Needed for `.sheet(item:)`. The struct declaration is untouched, and the conformance is a presentation concern, so it sits with the view rather than in `SaleDraft.swift`. | No — additive, and §7's declaration is unchanged |
| 04 | `VoidSheet` ships with no call site | 04 §13.9 requires it and `STRUCTURE.md` puts it in this module; 04 §3 enters it from module 05, which does not exist yet. It is complete and previewable; 05 wires it to `SaleServicing.void`. | No — the specs already said both things |

Record every deviation here the moment it happens. An undocumented deviation is how a codebase stops matching its spec.

## Open questions raised during build

- [x] **Resolved this session** — all four blockers (entities in 01, the seed's write path, CloudKit, repository surface) plus `JakartaDay`, `Rp` spacing, `AppContainer` scope, `BarcodeKind` edges, and seed suppliers. Answers are in the Deviations table above.
- [ ] **For module 05 — golden path §10 step 10 is unbuildable as written.** It says Chitato's history shows `+2 void · -2 sale · +24 restock · **+0 opening**`. But step 1 starts from an empty catalogue with no seed, step 2 creates Chitato with "no movement written", and foundations §9 / R-03-13 state that zero stock is the *absence* of movements, never a movement of zero. That `+0 opening` row cannot exist. `GoldenPathTests` will fail on it. Decide before session 5 whether to drop the row from the golden path or change the rule.
- [x] **Resolved in session 2 — `resolve(id:)` tolerates a seed identifier.** `ContactService.resolve` maps every read failure, `recordDoesNotExist` included, to `nil`; only a refused permission throws (R-02-4). Pinned by `test_R0204_seedIdentifierResolvesToNil`.
- [x] **Resolved in session 2** — the seven questions raised at the 02 plan gate (gone-state trigger, contact card, `.notDetermined`, host accessors, fake location, presenter naming, AC-02-8 provability). Answers are in the Deviations table above.
- [x] **Resolved in session 3 — `ContactField` is embedded, never constructed by a View.** `ProductFormViewModel` and `ProductDetailViewModel` each own a `ContactFieldViewModel` and read `.ref` at save time. Pinned by `test_formAttachesTheSupplierToTheProduct` and `test_detailPersistsASupplierChange`.
- [x] **Resolved at the session 3 plan gate** — the sixteen questions raised there (R-03-14's scope and its "missing" half, §9's missing errors and unnamed `validationFailed` fields, the seed's `stockQty` path, the §11 "Lihat" target, the five reason labels, the Jakarta formatter, `updatedAt` on stock changes, blank barcodes and blank searches, the two stock colours, `Sale`/`SaleLine` in a 03 test, and the three new test files). Answers are in the Deviations table above.
- [x] **Resolved in session 4 — a zero-quantity line aborts the tender, it is not skipped.** The session-3 note suggested skipping; R-04-16 makes the cart remove such a line, so a zero-qty draft can only be hand-built, and silently dropping a line the operator can see is worse than refusing. Pinned by `test_R0416_zeroQuantityLineIsRejected`.
- [x] **Resolved in session 4 — every stock call from 04 carries the sale's `id`.** `stage` shares `record`'s body, so R-03-13's pairing is enforced identically. Pinned by `test_AC0409_oneSaleMovementPerLine` and `test_AC0410_R0413_voidReversesMoneyAndStockTogether`.
- [x] **Resolved at the session 4 plan gate** — the ten questions raised there (`record` vs one save, R-03-14 against 04 §8, resolving a `productID` to a `Product`, a genuinely missing product, rollback after a failed commit, the unknown-barcode destination, where the customer field lives, a zero-qty line, cash with no amount, QRIS with an amount). Answers are in the Deviations table above.
- [ ] **For module 05 — `VoidSheet` exists and is unwired.** `Features/Sale/VoidSheet.swift` is complete: it takes a `Sale` and hands back a trimmed reason. 05's sale detail presents it and calls `SaleServicing.void(_:reason:)`. Do not reimplement it, and do not put void logic in `Features/History/`.
- [ ] **For module 05 — paging is `allSales(limit:offset:)`.** It windows a `createdAt`-descending list in memory (foundations §8 sizes this at ~18,000 rows a year). `sales(onJakartaDay:)` includes voided sales; excluding them from *totals* is R-05-2's job, not the repository's.

## Written test exemptions

Per `CONVENTIONS.md` §Testing, every rule gets a test or a written note saying why it cannot.

| Rule / AC | Why it has no automated test | How it is covered instead |
|---|---|---|
| AC-01-4 (camera denied) | Needs a real permission state; `AVCaptureDevice` authorization cannot be faked in a unit test. | `ScannerContractTests` pins the contract via `FakeScannerService`; the device path was exercised manually. |
| AC-01-5 (operator cancels) | Needs a presented `DataScannerViewController` and a human tap. | Same as above. |
| R-01-6 (symbologies) | The rule is enforced by *not asking* for other symbologies — VisionKit never delivers them, so there is nothing to assert against. | Enforced structurally in `BarcodeScanPresenter.symbologies`; verified by reading the one call site. |
| R-01-7 (`Info.plist` keys) | Not a runtime behaviour. | Verified against the **built** `JustScan.app/Info.plist` with `PlistBuddy`; recorded in the §12 table. |
| R-01-1 (no floats) | Not expressible as a unit test. | The two `grep` gates in the definition of done, run and recorded. |
| AC-02-7 (no `import Contacts` outside `Core/Contacts/`) | Not a runtime behaviour. | `grep -rn "^import Contacts"` across both targets, run and recorded in the §12 table. Made structurally true by `ContactAccess`. |
| AC-02-1 / AC-02-2, real picker | `CNContactPickerViewController` runs out-of-process and needs a human tap. | `ContactServiceContractTests` pins the contract via `FakeContactService`; the device path was exercised manually. |
| R-02-6 (only three keys requested) | The rule is enforced by *not asking* — there is nothing to assert against, exactly as with R-01-6. | Enforced structurally in `ContactService.keysToFetch`, one constant with one call site; verified by reading it. |
| AC-03-14 (`stockQty` assigned only in `StockService`) | Not a runtime behaviour. | `grep -rn "stockQty[ ]*[-+]\{0,1\}=" JustScan` — two hits, both in `StockService.swift` (`:63`, `:108`). The third is `Product.init`'s own `self.stockQty = stockQty`, which is the declaration, not a mutation. `SeedService` reaches it only through that initialiser and writes the matching `.opening` movement in the same `save()`. |
| AC-03-15 (no `@Attribute(.unique)`) | Not a runtime behaviour. | `grep -rn "@Attribute(.unique)\|@Query" JustScan JustScanTests` — every hit is a comment saying the app does not use them. |
| AC-03-1 / AC-03-2 / AC-03-7, real camera | The device path needs a `DataScannerViewController` and a human holding a packet of crisps. | `CatalogueViewModelTests` drives the identical decision through `FakeScannerService`; the ViewModel cannot tell the difference. |
| R-03-9 (a movement cannot be constructed without a reason) | Structural. `StockServicing.record` has no default for `reason`, so the compiler enforces it. | Verified by reading the one signature; every `record` call site names a reason. |
| R-03-10 (movements are never edited or deleted) | Structural. `StockMovementRepository` exposes `insert` and `movements` and nothing else. | `test_R0310_correctionIsAnOffsettingMovement` pins the *behaviour* — a wrong movement is corrected by an offset and the original survives. |
| AC-04-17 (`stockQty` never assigned inside `Features/Sale/`) | Not a runtime behaviour. | `grep -rn "stockQty[ ]*[-+]\{0,1\}=" JustScan/Features/Sale/` — zero hits. The only mention of `stockQty` in the whole folder is a **read** in `CartViewModel` for the R-04-6 warning chip, plus a comment in `SaleService`. |
| AC-04-18, the wall-clock half | "Interactive within 1 second" on a device is not a unit test. | `test_AC0418_tenderResetsTheCart` proves the reset is *synchronous* — the cart is empty the instant `tender` returns, and the success screen is an overlay on top of an already-ready screen, not something the reset waits for. The elapsed time is asserted under 1 s in-test and was observed instant in the simulator. |
| R-04-11 (a completed sale is immutable except for the void fields) | Partly structural: nothing on `SaleServicing` mutates a `Sale` except `void`. | `test_R0411_aCompletedSaleIsImmutableExceptForTheVoidFields` pins the consequence — after a void, number, total, line count, cash, change and method are all unchanged. |
| 04 §11's `20260821-001` literal | `complete` allocates from `Date()`, and no spec gives it an injectable clock. | `SaleNumberingTests` asserts the **shape** and the **sequence** against today's Jakarta key, and the day-boundary property directly against `SaleRepository.countOfSales(onJakartaDay:)` with §11's exact instants (21 Aug 23:58 WIB and 22 Aug 00:03 WIB, which are the same UTC day). |
| The scanner and picker paths in `CartView` | Same as AC-01-4/5 and AC-02-1/2: the camera and the contact picker need a device and a human. | `CartViewModelTests` drives every one of those decisions through `FakeScannerService` and `FakeContactService`; the ViewModel cannot tell the difference. The screen itself was launched in the simulator and its empty state, total, and disabled `Bayar`/`Buang` verified by eye. |

## Conventions added this build

Mirror anything added here into `CONVENTIONS.md`.

- **Apple-native components first, HIG-conformant.** Standing instruction from the operator, session 1. Reach for the system control before building one: `ContentUnavailableView` for every empty and error state, `TabView` with `Label`, `NavigationStack` with a large title, `.environment(_:)` + `@Environment(Type.self)` for `@Observable` injection rather than a hand-rolled `EnvironmentKey`, `UIBarButtonItem(systemItem: .cancel)` in the scanner. Applies to modules 02–05 too.
- **`@Observable` injection.** `AppContainer` is passed with `.environment(container)` and read with `@Environment(AppContainer.self)`. No custom `EnvironmentKey` — that is the documented pattern for an `@Observable` type.
- **`save()` on `ProductRepository` only.** The repositories share one `ModelContext`, so a single call commits everything staged in the operation. Do not add a second `save()` to another repository.
- **A framework type never crosses a module boundary.** If `Core/X` exists to be the only place that knows about framework `Y`, then `Y`'s types may not appear in `X`'s §7 exports — an exported enum forces the import back onto every caller and every fake. `ContactAccess` is the pattern (session 2).
- **A read-only screen never raises a permission prompt.** Permission is asked at the moment the operator asked for the thing that needs it, never as a side effect of rendering.
- **Test naming.** `test_<RuleID>_<behaviour>` where a rule exists (`test_R0102_…`, `test_AC0108_…`), plain descriptive names where the test pins a consequence rather than a rule.
- **A multi-repository operation stages, it does not record.** A service whose work must join another service's transaction exposes a non-committing variant; the caller commits once. `record` commits, `stage` does not (session 4).
- **`rollback()` sits beside `save()`.** A caught save error otherwise leaves the operation's inserts in the shared context, to be committed by the next successful save (session 4).
- **One instant per business operation, passed down.** `complete` captures `createdAt` once and hands it to the number, the sale, and every movement — hence `stage(… at:)` (session 4).

## Definition of done, per module

A module is done when **all** of these are true:

1. Every `AC-<module>-*` passes, reported as a pass/fail table — not "looks done".
2. Every `R-<module>-*` has a test, or a written note saying why it cannot have one.
3. No `Double`, `Float`, or `Decimal` in service or model code.
4. No `@Attribute(.unique)` anywhere.
5. Every model property is optional or defaulted; every relationship is optional with an explicit `inverse:`.
6. This file is updated and the work is committed.

## Golden path

The final gate before the project is called complete. Run the ten numbered steps in `00_foundations.md` §10 by hand, end to end, and record the result here.

| Run | Date | Result | Failures |
|---|---|---|---|
| — | — | not yet run | blocked until 05 — steps 7 and 9 need the history screens. Steps 1–6 and 8 are now buildable and are covered piecewise by `CatalogueServiceTests`, `StockServiceTests`, `SaleServiceTests`, `SaleNumberingTests` and `SaleVoidTests`. The step-10 `+0 opening` row is still unbuildable; see the open question above. |

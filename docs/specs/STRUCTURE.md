# Project Structure

> Referenced from `CONVENTIONS.md`. The top-level shape lives there; this file is the detail.
> **Create folders only when the session that owns them runs.** An empty directory tree invites an agent to fill it.

---

## Repository root

```
justscan/
├── CLAUDE.md                    ← verbatim copy of docs/specs/CONVENTIONS.md
├── README.md                    ← what this is, how to run it, link to docs/specs/
├── .gitignore                   ← Swift/Xcode template + .DS_Store
├── .claude/
│   └── commands/
│       ├── build-module.md
│       ├── verify-module.md
│       ├── resume.md
│       └── golden-path.md
├── docs/
│   ├── specs/                   ← the nine spec documents
│   │   ├── 00_foundations.md
│   │   ├── 01_app_shell.md
│   │   ├── 02_contact_link.md
│   │   ├── 03_catalogue.md
│   │   ├── 04_sale.md
│   │   ├── 05_history.md
│   │   ├── CONVENTIONS.md
│   │   ├── DECISIONS.md
│   │   ├── PROGRESS.md
│   │   └── STRUCTURE.md         ← this file
│   └── adr/
│       ├── 0001-swiftdata-over-coredata-grdb.md
│       ├── 0002-repository-enforced-uniqueness.md
│       └── 0003-mvvm-no-query-no-tca.md
├── JustScan.xcodeproj
├── JustScan/                         ← app target
└── JustScanTests/                    ← unit test target
```

Two targets. No UI test target — foundations §8 does not justify one, and `GoldenPathTests` drives the services directly instead.

---

## App target — `JustScan/`

### `App/` — composition root *(module 01)*

```
App/
├── JustScanApp.swift              @main. Builds the container, injects AppContainer.
├── AppContainer.swift        Every service and repository, constructed once.
├── RootTabView.swift         Jual · Produk · Riwayat. Jual selected on launch.
└── StoreUnavailableView.swift  Shown only when the store will not load (01 §8).
```

`Info.plist` and `Assets.xcassets` sit at the target root, not in `App/` — the
Xcode target's `INFOPLIST_FILE` points there, and the file is the one member
excluded from the synchronized group.

**Why `ContactPickerPresenter`, not `ContactPickerView`.** Identical reasoning to
the scanner below, and the same conclusion reached in session 2: the export is
`pick() async -> ContactRef?`, a value a ViewModel awaits.

**Why `BarcodeScanPresenter`, not `DataScannerView`.** This file was specced as a
`UIViewControllerRepresentable`. It is a presenter instead, because the exported
contract is `ScannerServicing.scan() async throws -> String?` — a value a
ViewModel awaits. A representable would put scanner lifetime and results in the
*view*, which inverts the layering rule. Changed in session 1.

`AppContainer` is the only place a concrete service is constructed. Views receive it through `@Environment`. This is what makes `InMemoryProductRepository` substitutable in tests without a DI framework.

### `Models/` — `@Model` types only, zero logic *(modules 03, 04)*

```
Models/
├── Product.swift             + computed `supplier: ContactRef?`
├── StockMovement.swift       + computed `reason: StockReason`
├── Sale.swift                + computed `method`, `status`, `customer`
└── SaleLine.swift
```

Enum-backed `String` columns (`reasonRaw`, `statusRaw`, `paymentMethodRaw`) live on the model; the typed accessor is a computed property in the same file. That is the one logic exception — no other behaviour belongs here.

### `Core/` — shared, feature-agnostic *(module 01, plus 02 and Stock)*

```
Core/
├── Money/
│   └── Rp.swift                       format(_:) → "Rp 12.000"
├── Time/
│   └── JakartaDay.swift               THE day-boundary helper. Nothing else computes days.
│                                      Also owns every display formatter, because one that
│                                      forgets `timeZone` is the bug this type exists to
│                                      prevent: `shortDateTime(_:)` (session 3, `d MMM, HH:mm`)
│                                      and `time(_:)` / `longDate(_:)` / `fullDateTime(_:)`
│                                      plus `previousDay(_:)` — 05 §10's `HH:mm`,
│                                      `d MMM yyyy`, and "kemarin" (session 5).
├── Barcode/
│   ├── BarcodeKind.swift              .gtin / .internalCode / .unknown
│   ├── ScannerService.swift           protocol + concrete
│   └── BarcodeScanPresenter.swift     DataScannerViewController wrapper
├── Contacts/                          ← module 02. ONLY folder importing Contacts.
│   ├── ContactRef.swift               value type + the R-02-3 fallback chain
│   ├── ContactAccess.swift            the status, without CNAuthorizationStatus
│   ├── ContactService.swift           protocol + concrete
│   ├── ContactPickerPresenter.swift   CNContactPickerViewController wrapper
│   ├── ContactFieldViewModel.swift    decides the three states of 02 §10
│   └── ContactField.swift             the shared 3-state row (03 and 04 both embed it)
├── Stock/                             ← owned by 03, lives in Core because 04 calls it
│   ├── StockReason.swift              + `requiresSaleID`, which is R-03-13 made enforceable
│   └── StockService.swift             protocol + concrete. `stage()` added session 4:
│                                      `record` without the commit, so 04 can put a sale,
│                                      its lines and every movement in one save (R-04-15).
├── Persistence/
│   ├── PersistenceController.swift    the Schema and ModelContainer
│   ├── ProductRepository.swift        protocol + SwiftDataProductRepository. `find(id:)`
│   │                                  added session 3: it is how R-03-14 detects "missing".
│   │                                  `findAny(id:)` and `rollback()` added session 4 —
│   │                                  the deleted-inclusive read 04 §8 needs, and the
│   │                                  discard half of the one-commit-per-operation pair.
│   ├── StockMovementRepository.swift
│   └── SaleRepository.swift           incl. number allocation (R-04-4)
├── Errors/
│   ├── POSError.swift
│   └── POSError+Message.swift         Indonesian strings. An error without one is a bug.
└── Debug/
    └── SeedService.swift              #if DEBUG only
```

`Core/Stock/` looks misplaced next to `Features/Catalogue/`, and it is deliberate. Module 03 *owns* the stock rules, but module 04 calls them on every sale. Putting `StockService` in `Features/Catalogue/` would make Sale import a feature folder to do its most important job. It sits in `Core/` because two features depend on it — that is the actual test for what belongs in `Core/`.

### `Features/` — one folder per module

```
Features/
├── Catalogue/                         ← module 03
│   ├── CatalogueService.swift         protocol + concrete
│   ├── ProductListView.swift
│   ├── ProductListViewModel.swift     + the nested `Route` the stack navigates on
│   ├── ProductDetailView.swift
│   ├── ProductDetailViewModel.swift
│   ├── ProductFormView.swift          new + edit, one view
│   ├── ProductFormViewModel.swift     holds the R-03-8 internal-code warning
│   ├── AddStockSheet.swift
│   ├── AdjustStockSheet.swift         takes a counted qty, not a delta
│   └── StockMovementRow.swift
├── Sale/                              ← module 04
│   ├── SaleService.swift              protocol + concrete. complete() and void().
│   ├── SaleDraft.swift                DraftLine + the in-memory cart. Never persisted.
│   ├── CartView.swift
│   ├── CartViewModel.swift            R-04-2 line merging lives here, and the customer
│   │                                  `ContactFieldViewModel` (04 §3.9 puts it on the cart)
│   ├── CartLineRow.swift
│   ├── TenderSheet.swift
│   ├── TenderViewModel.swift          the sheet's arithmetic, so the sheet does none
│   ├── CashQuickPicks.swift           R-04-9. Pure function, easy to test.
│   ├── PaymentSuccessView.swift       change due, auto-dismiss 3 s
│   └── VoidSheet.swift                required reason
└── History/                           ← module 05. Reads only: no service, no
    │                                     repository, no `ModelContext` (R-05-8).
    ├── DaySummary.swift               + the aggregation function and `DaySummary.Group`
    ├── HistoryView.swift              + the private summary card and day header
    ├── HistoryViewModel.swift         scope, paging, and which subtotals are honest
    ├── SaleDetailView.swift           presents module 04's `VoidSheet`, owns none of it
    ├── SaleDetailViewModel.swift      added session 5 — a View may not call a Service,
    │                                  and **Batalkan** is a service call
    └── SaleRow.swift                  + `PaymentMethod.label` / `.icon`, the two
                                       operator-facing strings 05 §10 needs
```

---

## Test target — `JustScanTests/`

```
JustScanTests/
├── Support/
│   ├── TestContainer.swift             isStoredInMemoryOnly: true
│   ├── Fixtures.swift                  chitato(), tehBotol(), gorengan()
│   ├── FakeContactService.swift
│   ├── FakeScannerService.swift
│   ├── InMemoryProductRepository.swift      a `save()` that can be made to fail
│   ├── InMemoryStockMovementRepository.swift
│   └── FailingSaveProductRepository.swift   added session 4 — the same forced failure
│                                            over a **real** store, so AC-04-16 can ask a
│                                            second context what actually landed
├── Core/
│   ├── RpTests.swift                   R-01-2 — the five exact strings
│   ├── BarcodeKindTests.swift          R-01-8 — the five exact classifications
│   ├── JakartaDayTests.swift           run with TZ=UTC. This one catches real bugs.
│   ├── ContactRefTests.swift           R-02-3 fallback chain, R-02-5 pairing
│   ├── ContactServiceContractTests.swift  the §7 contract 03 and 04 are written against
│   ├── ContactFieldViewModelTests.swift   the three states of 02 §10
│   └── ContactHostMappingTests.swift   R-02-1 / R-02-5 through a real store, AC-02-8
├── Catalogue/
│   ├── CatalogueServiceTests.swift     R-03-1..5, R-03-12, R-03-14, AC-03-13
│   ├── StockServiceTests.swift         R-03-6..11, R-03-13 — the ledger arithmetic
│   └── CatalogueViewModelTests.swift   AC-03-1/2/7 — the scan pivot and the R-03-8 warning
├── Sale/
│   ├── SaleServiceTests.swift          R-04-3, R-04-5..8, R-04-15 (write this one first)
│   ├── SaleNumberingTests.swift        R-04-4 across a Jakarta day boundary
│   ├── SaleVoidTests.swift             R-04-11..14
│   ├── CashQuickPicksTests.swift       R-04-9
│   ├── CartViewModelTests.swift        R-04-2, R-04-16, AC-04-1/2/18
│   └── TenderViewModelTests.swift      added session 4 — the sheet's own decisions
├── History/
│   ├── DaySummaryTests.swift           R-05-1..7, incl. the §11 worked example
│   ├── HistoryViewModelTests.swift     added session 5 — scopes, paging, AC-05-7
│   └── SaleDetailViewModelTests.swift  added session 5 — R-05-4, AC-05-6, the void entry
└── GoldenPathTests.swift               all ten steps, one test, fresh container.
                                        NOT a module-05 file: 05 §12 defines no criterion
                                        for it and 05 §13 does not list it. It belongs to
                                        the `/golden-path` gate, which runs after 05.
                                        Reassigned session 5.
```

Test naming: `test_R0403_snapshotsPriceAtTender`. The rule ID in the name is what lets `/verify-module` map tests to rules mechanically instead of by reading them.

---

## Two conventions this file amends

**1. Protocol and implementation share a file.** `CONVENTIONS.md` says one type per file; a protocol plus its primary conformance is the exception, named for the concrete type. `StockService.swift` holds `StockServicing` and `StockService`. Fakes live in `JustScanTests/Support/`, never beside the real thing.

**2. Two protocol naming patterns coexist.** Services use `-ing` (`StockServicing`), because the spec §7 exports already lock those names. Repositories use a plain protocol with a prefixed conformance (`ProductRepository` ← `SwiftDataProductRepository`), because `ProductRepositoring` is not a word. It is a minor inconsistency; it is recorded here rather than smoothed over, and it is not worth churning the specs to fix.

---

## Module boundaries are convention, not enforcement

`Features/Sale/` importing `CatalogueServicing` is a legal cross-module call under foundations §6 — but in a single Xcode target, nothing *stops* `SaleService` from reaching into `ProductRepository` directly and writing `stockQty` itself, which R-03-6 forbids.

Real enforcement would mean local SPM packages, one per module, with explicit dependency declarations. That buys compile-time boundaries and costs a day of build configuration plus friction on every file added.

**For a 10-day project, take the convention.** The guard is `AC-04-17` — `grep` for `stockQty` inside `Features/Sale/` — which catches the exact violation that matters for the cost of one line in `/verify-module`. Revisit if a second developer joins, because conventions hold in one head far better than in two.

---

## Which session creates what

| Session | Module | Creates |
|---|---|---|
| 1 | 01 App shell | `App/`, `Models/` (storage-only declarations), `Core/Money`, `Core/Time`, `Core/Barcode`, `Core/Stock/StockReason`, `Core/Errors`, `Core/Persistence`, `Core/Debug`, `JustScanTests/Support`, `JustScanTests/Core`, `JustScanTests/Debug` |
| 2 | 02 Contact link | `Core/Contacts/` |
| 3 | 03 Catalogue | `Models/Product`, `Models/StockMovement`, `Core/Stock/`, the two repositories, `Features/Catalogue/`, `JustScanTests/Catalogue/` |
| 4 | 04 Sale | `SaleRepository` (filled), `Features/Sale/`, `JustScanTests/Sale/`. `Models/Sale` and `Models/SaleLine` were already declared in session 1 and needed no field changes. |
| 5 | 05 History | `Features/History/`, `JustScanTests/History/`. `GoldenPathTests` belongs to the `/golden-path` gate, not to this session — see the test tree above. |

Roughly 60 Swift files. If a session is producing appreciably more than its row above, it has taken on work that belongs to a later module — stop and check the spec's non-goals.

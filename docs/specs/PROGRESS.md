# Build Progress

Read this file **first** at the start of every session. Update it at the end of every session, before committing.

## Current

- **Active module:** 02 Contact link — **done, 8/8**
- **Session goal:** 02 Contact Link ✅
- **Next up:** 03 Catalogue

## Status

| Module | Status | Acceptance criteria passing | Notes |
|---|---|---|---|
| 01 App shell | **done** | **8/8** | 52 tests, 125 expectations, all passing. CloudKit mirroring verified live. |
| 02 Contact link | **done** | **8/8** | 31 new tests, 83 passing overall. Ships no screens — one shared `ContactField` that 03 and 04 embed. |
| 03 Catalogue | todo | 0/16 | Largest data model |
| 04 Sale | todo | 0/18 | Largest module. Build nothing else that session. |
| 05 History | todo | 0/9 | Read-only |

**Total: 16/59 acceptance criteria.**

## Session order and sizing

| Session | Module | Watch for |
|---|---|---|
| 1 | 01 App shell | Patterns set here are copied four more times. Do not rush the repository protocols. |
| 2 | 02 Contact link | Small. If it finishes early, do **not** start 03 — write its tests instead. |
| 3 | 03 Catalogue | Build `StockService` before any view. R-03-11 atomicity is the hard part. |
| 4 | 04 Sale | Write AC-04-16 (no partial write) **first**, before the commit path exists. |
| 5 | 05 History | Build `DaySummary` and the Jakarta-day helper before any view. |

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

Record every deviation here the moment it happens. An undocumented deviation is how a codebase stops matching its spec.

## Open questions raised during build

- [x] **Resolved this session** — all four blockers (entities in 01, the seed's write path, CloudKit, repository surface) plus `JakartaDay`, `Rp` spacing, `AppContainer` scope, `BarcodeKind` edges, and seed suppliers. Answers are in the Deviations table above.
- [ ] **For module 05 — golden path §10 step 10 is unbuildable as written.** It says Chitato's history shows `+2 void · -2 sale · +24 restock · **+0 opening**`. But step 1 starts from an empty catalogue with no seed, step 2 creates Chitato with "no movement written", and foundations §9 / R-03-13 state that zero stock is the *absence* of movements, never a movement of zero. That `+0 opening` row cannot exist. `GoldenPathTests` will fail on it. Decide before session 5 whether to drop the row from the golden path or change the rule.
- [x] **Resolved in session 2 — `resolve(id:)` tolerates a seed identifier.** `ContactService.resolve` maps every read failure, `recordDoesNotExist` included, to `nil`; only a refused permission throws (R-02-4). Pinned by `test_R0204_seedIdentifierResolvesToNil`.
- [x] **Resolved in session 2** — the seven questions raised at the 02 plan gate (gone-state trigger, contact card, `.notDetermined`, host accessors, fake location, presenter naming, AC-02-8 provability). Answers are in the Deviations table above.
- [ ] **For module 03 — `ContactField` is embedded, never constructed by a View.** The host ViewModel owns the `ContactFieldViewModel` and reads `.ref` at save time. `ProductFormViewModel` must hold one, or the supplier will not reach `Product.supplier`.

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

## Conventions added this build

Mirror anything added here into `CONVENTIONS.md`.

- **Apple-native components first, HIG-conformant.** Standing instruction from the operator, session 1. Reach for the system control before building one: `ContentUnavailableView` for every empty and error state, `TabView` with `Label`, `NavigationStack` with a large title, `.environment(_:)` + `@Environment(Type.self)` for `@Observable` injection rather than a hand-rolled `EnvironmentKey`, `UIBarButtonItem(systemItem: .cancel)` in the scanner. Applies to modules 02–05 too.
- **`@Observable` injection.** `AppContainer` is passed with `.environment(container)` and read with `@Environment(AppContainer.self)`. No custom `EnvironmentKey` — that is the documented pattern for an `@Observable` type.
- **`save()` on `ProductRepository` only.** The repositories share one `ModelContext`, so a single call commits everything staged in the operation. Do not add a second `save()` to another repository.
- **A framework type never crosses a module boundary.** If `Core/X` exists to be the only place that knows about framework `Y`, then `Y`'s types may not appear in `X`'s §7 exports — an exported enum forces the import back onto every caller and every fake. `ContactAccess` is the pattern (session 2).
- **A read-only screen never raises a permission prompt.** Permission is asked at the moment the operator asked for the thing that needs it, never as a side effect of rendering.
- **Test naming.** `test_<RuleID>_<behaviour>` where a rule exists (`test_R0102_…`, `test_AC0108_…`), plain descriptive names where the test pins a consequence rather than a rule.

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
| — | — | not yet run | blocked until 05 — steps 2–10 need modules 03 and 04. See the step-10 open question above. |

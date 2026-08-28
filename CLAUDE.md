# CONVENTIONS

> Save this at the repo root as `CLAUDE.md` so it loads automatically in every Claude Code session.
> Specs say *what the software does*. This file says *how the code is written*.

---

## Working agreement (read every session)

- Specs live in `docs/specs/`. Build order is in `00_foundations.md` §5.
- Read `PROGRESS.md` **first** — it says where we are and what is next.
- Build strictly to the module spec. **Do not invent behavior.** If the spec is ambiguous, silent, or conflicts with another spec, **STOP and ask.**
- A `⚠️ OPEN` marker in a spec is a hard stop, not a suggestion.
- Match the patterns of already-built modules. If you need a pattern that is not in the repo yet, justify it in `PROGRESS.md` and add it here.
- A module is DONE only when **every** one of its acceptance criteria passes, reported as a table.
- One module per session. Do not start the next module early.

---

## Repo layout

**Full file-by-file tree: `docs/specs/STRUCTURE.md`.** The shape:

```
JustScan/
├── App/                    # entry point, tab shell, AppContainer (DI root)
├── Models/                 # @Model types only. No logic.
├── Core/                   # shared, feature-agnostic
│   ├── Money/ Time/ Barcode/ Errors/ Persistence/ Debug/
│   ├── Contacts/           # module 02 — the ONLY place importing Contacts
│   └── Stock/              # owned by 03, lives here because 04 calls it
├── Features/
│   ├── Catalogue/  Sale/  History/
└── JustScanTests/
```

**What belongs in `Core/`:** anything two or more features depend on. That is the whole test — not "it feels generic".

One type per file, filename matching the type, **except** a protocol and its primary conformance, which share a file named for the concrete type (`StockService.swift` holds `StockServicing` and `StockService`). Fakes live in `JustScanTests/Support/`, never beside the real implementation.

**Create folders when the session that owns them runs.** An empty tree scaffolded up front invites an agent to fill it with work that belongs to a later module.

---

## The layering rule

```
View  →  ViewModel  →  Service  →  Repository  →  ModelContext
```

Each arrow is one-directional. Each layer may only call the one to its right.

| Layer | May | May **not** |
|---|---|---|
| View | Render, call ViewModel methods | Import SwiftData · touch `ModelContext` · do money arithmetic · use `@Query` |
| ViewModel | Hold view state, call Services, format for display | Touch `ModelContext` · hold business rules |
| Service | Every business rule. Validate, decide, orchestrate, `save()` | Import SwiftUI · know about views |
| Repository | Fetch, insert, save | Hold rules · validate · decide anything |
| Model | Store data | Contain logic beyond trivial computed properties |

**`@Query` is banned in views.** It is idiomatic SwiftUI and it welds the view to the store, making rules untestable. This is a recorded trade-off (ADR-03), not an oversight. Do not "fix" it.

**A framework type never crosses a module boundary.** When a `Core/` folder exists to be the only place that knows about a framework — `Contacts`, `VisionKit` — that framework's types may not appear in its §7 exports. An exported `CNAuthorizationStatus` forces `import Contacts` back onto every caller *and every fake*, which is the exact coupling the folder was created to prevent. Export a type the module owns instead (`ContactAccess`). Added session 2.

**A read-only screen never raises a permission prompt.** Permission is asked at the moment the operator asked for the thing that needs it, never as a side effect of rendering a screen they only wanted to read. Added session 2.

**A multi-repository operation stages; it does not record.** When a service method must commit work belonging to another service in the same transaction, that other service exposes a non-committing variant and the caller commits once. `StockServicing.record` commits itself; `StockServicing.stage` does not, which is what lets `SaleService.complete` put a sale, its lines, and every movement in one `save()` (R-04-15). A method that commits per item cannot be composed into a transaction. Added session 4.

**`rollback()` sits beside `save()`, and only a failed commit calls it.** A caught save error leaves the operation's inserts in the shared `ModelContext`, where the next successful save commits them — so a retried tender would commit the abandoned attempt too. `ProductRepository.rollback()` discards them. It lives on `ProductRepository` for the same reason `save()` does. Added session 4.

**An instant is captured once per operation and passed down.** `SaleService.complete` captures `createdAt` at the start and hands it to the number, the sale, and every movement, which is why `stage` takes an `at:` parameter. Two calls to `Date()` inside one business operation is a bug waiting for a day boundary. Added session 4.

---

## SwiftData rules — violating these breaks iCloud silently

Every one of these is mandatory from day one, even though CloudKit is off. Full checklist: `docs/specs/CLOUDKIT_CHECKLIST.md`.

```swift
@Model final class Example {
    var id: UUID = UUID()              // ✅ defaulted
    var name: String = ""              // ✅ defaulted
    var note: String?                  // ✅ optional
    var deletedAt: Date?               // ✅ soft delete

    @Relationship(deleteRule: .cascade, inverse: \Child.parent)
    var children: [Child]? = []        // ✅ optional, explicit inverse
}
```

| Rule | Consequence of breaking it |
|---|---|
| Every stored property optional **or** defaulted | CloudKit refuses the schema |
| **Never** `@Attribute(.unique)` | CloudKit does not support unique constraints |
| Every relationship optional | CloudKit syncs graphs partially |
| Every relationship has an explicit `inverse:` | Crashes on some iOS versions; required by CloudKit |
| Delete rules `.cascade` or `.nullify`, never `.deny` | CloudKit requirement |
| Soft delete via `deletedAt`; never `modelContext.delete()` | Hard deletes do not propagate |

Uniqueness lives in the repository. `ProductRepository.findBy(barcode:)` before every insert, **inside the service call**, not in the ViewModel.

---

## UI

**Apple-native first.** Reach for the system control before building one, and follow the Human Interface Guidelines. Established session 1, applies to every module.

| Need | Use |
|---|---|
| Empty state, error state, placeholder | `ContentUnavailableView` |
| Tab shell | `TabView` + `Label`, one `.tag` per case |
| Screen container | `NavigationStack`, large title |
| Injecting an `@Observable` | `.environment(value)` → `@Environment(Type.self)`. **No hand-rolled `EnvironmentKey`.** |
| Money on screen | `Rp.format(_:)`, never string interpolation |
| A dismissable sheet | A visible system Cancel button. Never a modal the operator can be trapped in. |

Dynamic Type is supported everywhere; the sale screen must stay usable at XL sizes. **Portrait only, iPhone only.**

The two go together and are one decision, not two (D-19). Apple permits a
portrait-only iPhone app; an iPad build must support all four orientations for
multitasking, and rejects the upload otherwise (`ITMS-90474`). The sale screen
puts its total and buttons in the bottom third to be reachable one-handed at a
counter — that is a phone layout, so `TARGETED_DEVICE_FAMILY = 1`. Do not add
iPad back without also reversing "Portrait only" and auditing every screen in
landscape.

---

## Repository `save()`

`save()` lives on `ProductRepository` **alone**. Every repository shares one `ModelContext`, so that single call commits everything staged during the operation — a product insert and its stock movements land together (R-03-11, R-04-15). Do not add a second `save()` to another repository; two `save()` calls in one business operation is the review failure the transaction rule exists to prevent.

---

## Money

**`Int` rupiah. Always.** No `Decimal`, no `Double`, no `Float` in `Core/`, `Models/`, or any `*Service.swift`.

- Field names end in `Rp`: `priceRp`, `totalRp`, `changeRp`.
- Display only through `Rp.format(_:)` → `"Rp 12.000"`.
- Never format money inside a View with string interpolation.
- `nil` money means "not applicable" (QRIS change). `0` means "the amount was zero". Never conflate them.

---

## Time

- Store `Date`. Group and display in **`Asia/Jakarta`**, always, regardless of device timezone.
- One shared helper owns day boundaries. No feature computes its own.
- Every entity has `createdAt: Date = Date()`.
- In `SaleService.complete`, capture `createdAt` **once** and reuse that single value for the number, the sale, and every movement.

---

## Naming

| Thing | Convention | Example |
|---|---|---|
| Model | Singular `UpperCamelCase` | `Product`, `SaleLine` |
| Service | `<Noun>Service` + `<Noun>Servicing` protocol | `StockService`, `StockServicing` |
| Repository | `<Noun>Repository` | `ProductRepository` |
| Enum backing | `<name>Raw: String` on the model, typed accessor in an extension | `statusRaw` → `status` |
| Test | `test_<rule id>_<behaviour>` | `test_R0403_snapshotsPriceAtTender` |

Code, comments, and identifiers in **English**. All operator-facing strings in **Indonesian**.

**`POSError` keeps its name**, deliberately — it names the *domain* (point of sale), not the *product*. Product names change; the domain does not. Same reasoning for `Rp`: the unit outlives the app. If you'd rather it match the target, rename it to `JustScanError` in session 1 and nowhere later — it appears in all five modules and every test.

---

## Errors

- `POSError` (foundations §7) is the only error type crossing a service boundary.
- A repository may throw SwiftData errors; the service wraps them in `.persistenceFailed`.
- **Never** `try?` on a write path. A swallowed save failure is a lost sale.
- Every error has an Indonesian user-facing message. An error without one is a bug.

---

## Transactions

**One `save()` per business operation.** `SaleService.complete` inserts the sale, its lines, and every stock movement, then saves **once**. A partial write is the worst class of bug this system can produce.

Any service method that calls `save()` more than once is a review failure.

---

## Testing

- Test the **service layer**. Services take repository protocols, so tests inject fakes or in-memory containers.
- Swift Testing (`@Test`, `#expect`), not XCTest.
- In-memory container: `ModelConfiguration(isStoredInMemoryOnly: true)`.
- Every `R-<module>-<n>` gets a test, or a note in `PROGRESS.md` saying why it cannot.
- Every `AC-<module>-<n>` is answerable yes/no by running the software.
- Do not test SwiftUI views. Test the ViewModel and the Service.

---

## Definition of done

1. Every acceptance criterion passes, reported as a pass/fail table.
2. Every rule has a test or a written exemption.
3. No `Double`, `Float`, or `Decimal` in service or model code.
4. No `@Attribute(.unique)` anywhere.
5. No `@Query` in any view.
6. No `save()` inside `Features/History/`.
7. `PROGRESS.md` updated. Work committed.

---

## When the spec and the code disagree

The spec wins, **unless** the spec is wrong — in which case stop, say so, and update the spec before writing the code. Never leave the two disagreeing. Record it in `PROGRESS.md` under Deviations.

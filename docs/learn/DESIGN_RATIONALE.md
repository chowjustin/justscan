# Design Rationale

> Companion to `docs/specs/`. The specs say *what* the system does. `DECISIONS.md` says *what was decided*. This file says **why**, at the depth you'd need to defend the choice or reverse it deliberately.
>
> Every entry has the same five parts. The last one — **How you'd know this was wrong** — matters most. A decision you can't falsify isn't engineering, it's taste.

---

## Contents

1. [Why layers at all](#1-why-layers-at-all)
2. [Why MVVM — not TCA, not plain SwiftUI](#2-why-mvvm--not-tca-not-plain-swiftui)
3. [Why a repository layer](#3-why-a-repository-layer)
4. [Why `@Query` is banned](#4-why-query-is-banned)
5. [Why SwiftData](#5-why-swiftdata)
6. [Why the CloudKit-shaped schema, today](#6-why-the-cloudkit-shaped-schema-today)
7. [Why money is `Int`](#7-why-money-is-int)
8. [Why an append-only stock ledger](#8-why-an-append-only-stock-ledger)
9. [Why `SaleLine` snapshots name and price](#9-why-saleline-snapshots-name-and-price)
10. [Why `productID` is a weak `UUID?`](#10-why-productid-is-a-weak-uuid)
11. [Why soft delete](#11-why-soft-delete)
12. [Why one `save()` per operation](#12-why-one-save-per-operation)
13. [Why the cart lives in memory](#13-why-the-cart-lives-in-memory)
14. [Why `nil` is not `0`](#14-why-nil-is-not-0)
15. [Why zero stock warns instead of blocking](#15-why-zero-stock-warns-instead-of-blocking)
16. [Why sale numbers have no gaps](#16-why-sale-numbers-have-no-gaps)
17. [Why every day boundary is Asia/Jakarta](#17-why-every-day-boundary-is-asiajakarta)
18. [Why contacts are stored twice](#18-why-contacts-are-stored-twice)
19. [Why there is no auth](#19-why-there-is-no-auth)
20. [Why no event bus](#20-why-no-event-bus)
21. [Why one Xcode target](#21-why-one-xcode-target)
22. [Why zero third-party dependencies](#22-why-zero-third-party-dependencies)
23. [The meta-lesson: which decisions deserved this treatment](#23-the-meta-lesson)

---

## 1. Why layers at all

**Decision.** `View → ViewModel → Service → Repository → ModelContext`, one direction only.

**What it's for.** Putting each kind of change in exactly one place. A pricing rule change touches a service. A layout change touches a view. A switch from SwiftData to GRDB touches repositories. Without layers, all three touch the same file.

**Why it must be so.** The alternative — SwiftUI views calling `modelContext` directly — is genuinely faster to write, and it's what most tutorials show. It fails on a specific axis: **you cannot test a business rule without instantiating a view.** R-04-8 says cash below total must throw with the exact shortfall. With layers, that's a three-line unit test against `SaleService`. Without them, it's a UI test that launches a simulator, taps through a cart, and asserts on a label.

The rule count tells you whether this is worth it. This system has 52 numbered rules. At 52 rules, untestable business logic is not a style preference, it's a defect generator.

**What it costs.** Roughly 3–4 extra files per feature and a real amount of forwarding code — a ViewModel method that does nothing but call a service method. That forwarding feels like waste right up until the day two views need the same rule.

**How you'd know this was wrong.** If, at the end, most ViewModels turn out to be pure pass-throughs with no state and no formatting, the layer wasn't earning its place and views could have called services directly. Check this honestly in the retro — it's the most likely over-engineering in the whole design.

---

## 2. Why MVVM — not TCA, not plain SwiftUI

**Decision.** MVVM with `@Observable` classes. No Composable Architecture. No `@Query`-driven views.

**What it's for.** A middle point between "no structure" and "a framework with its own worldview."

**Why it must be so.** Consider the three options against your actual goal, which is *learning Swift*:

| | Plain SwiftUI | MVVM + `@Observable` | TCA |
|---|---|---|---|
| Time to first screen | fastest | medium | slowest |
| Business rules testable without UI | no | yes | yes |
| New concepts to learn | none | 2–3 | 15+ |
| What you're learning | SwiftUI | Swift and SwiftUI | TCA |

TCA is genuinely excellent, and < cite index="45-1">it's the right call when state determinism is a product requirement</cite> — think a trading terminal where you must replay exactly what happened. This is a shop till with 52 rules and one operator. Choosing TCA here means spending your ten days learning reducers, effects, and dependency clients, and finishing able to write TCA rather than able to write Swift.

**What it costs.** More boilerplate than plain SwiftUI. Less compile-time guarantee than TCA — nothing stops a view from holding state that should live in a ViewModel.

**How you'd know this was wrong.** If ViewModels start holding each other's state, or if you find yourself needing to replay a sequence of actions to reproduce a bug, MVVM has run out and TCA's discipline would have paid.

---

## 3. Why a repository layer

**Decision.** Services depend on `ProductRepository` (a protocol). `SwiftDataProductRepository` is one conformance; `InMemoryProductRepository` is another.

**What it's for.** Two things, and the second is the real one.

1. **Testability.** A service test injects a fake, runs in microseconds, has no disk.
2. **Uniqueness enforcement.** Because CloudKit forbids `@Attribute(.unique)` (§6), the barcode rule has nowhere else to live. The repository is the only chokepoint every insert must pass through.

**Why it must be so.** Without it, R-03-1 has no home. You'd check for a duplicate barcode in the ViewModel — and then the next feature that creates a product (an import, a seed, a fixture) skips the check, and you have two products with one barcode and no error anywhere. That's why R-03-2 is written as it is: the check must be *inside* `CatalogueService.create`, not upstream of it.

**What it costs.** A protocol and a conformance per entity. Four entities, so four extra protocols.

**How you'd know this was wrong.** If you never write a fake, and every test uses an in-memory `ModelContainer` anyway, the protocol bought you nothing and the concrete type would have been fine. Notice that if it happens.

---

## 4. Why `@Query` is banned

**Decision.** No `@Query` in any view. ViewModels fetch through services.

**What it's for.** Keeping the "what data do I show" decision testable.

**Why it must be so.** `@Query` is genuinely lovely — one line, auto-updating, no wiring. It also does three things quietly:

- It puts a **fetch predicate inside a view**, where no test can reach it. R-03-12 says soft-deleted products are excluded from every list. With `@Query`, that rule lives in a view's property wrapper.
- It requires the view to **import SwiftData**, which welds your UI to your persistence choice. ADR-01 says SwiftData is reversible via repositories — `@Query` in views silently un-reverses it.
- It makes the view **own a fetch**, so two views showing the same list can disagree about filtering.

**What it costs.** Real: you lose automatic UI updates. A ViewModel must re-fetch after a mutation, which is manual and forgettable, and "I saved but the list didn't update" will be a bug you hit at least twice.

**How you'd know this was wrong.** If you end up writing a manual refresh mechanism that reimplements observation badly, `@Query` was the better trade and the rule should be relaxed for read-only screens.

---

## 5. Why SwiftData

**Decision.** SwiftData, not Core Data, not GRDB.

**What it's for.** Persistence with the least code and the least ceremony on a greenfield iOS 17+ app.

**Why it must be so.** < cite index="65-1">SwiftData is the choice for a greenfield SwiftUI app on iOS 17+ with the least code; GRDB is for real SQL power and complex queries; Core Data is for an existing codebase or pre-iOS-17 support.</cite> This is greenfield, iOS 17+, and the queries are trivial — fetch by ID, fetch by barcode, fetch by day.

You should know what you're accepting. < cite index="72-1">SwiftData supports only lightweight migrations, can struggle with large object graphs because it loads eagerly rather than faulting, and its collections don't support sort descriptors the way Core Data fetch requests do.</cite> All three would bite a bigger POS. At 2,000 products and 18,000 sales a year they do not.

**What it costs.** If reporting grows — profit by supplier, stock valuation over time — you'll want SQL and hit SwiftData's ceiling. The repository layer is the insurance premium already paid.

**How you'd know this was wrong.** The first time you want a query SwiftData can't express and you find yourself fetching everything into memory to filter it in Swift. That's the signal to swap the repository conformance for GRDB.

---

## 6. Why the CloudKit-shaped schema, today

**Decision.** Every property optional or defaulted, no `@Attribute(.unique)`, every relationship optional with an explicit inverse, soft deletes — even though CloudKit is off.

**What it's for.** Making "turn on iCloud" a checkbox instead of a migration.

**Why it must be so.** This is the most important entry in this document, because it's the one that looks like premature optimization and isn't. < cite index="165-1">You cannot use `@Attribute(.unique)` on any property you want to sync, all properties must have default values or be optional, and all relationships must be optional.</cite> < cite index="161-1">Relationships must also have an inverse, and delete rules cannot be `.deny`.</cite>

And the failure mode is the reason this can't wait: < cite index="165-1">if you don't follow these requirements, iCloud sync fails silently.</cite> Not a crash. Not a compiler error. It just doesn't sync, and you find out when the owner's second device shows an empty catalogue.

The general lesson: **a stated future requirement that constrains your schema is a present requirement.** Schema decisions are the least reversible thing in an app, because unlike code, they have data sitting on top of them.

**What it costs.** Almost nothing today — a few `= UUID()` defaults — and the loss of database-enforced uniqueness, which moves to the repository (§3).

**How you'd know this was wrong.** If iCloud is genuinely never turned on, you carried optional-everywhere for no benefit. That's a small, recoverable loss; the reverse mistake is not.

---

## 7. Why money is `Int`

**Decision.** `Int` rupiah. No `Decimal`, no `Double`, no `Float`.

**What it's for.** Exactness, with no scaling factor to remember.

**Why it must be so.** `Double` is disqualified everywhere in finance — `0.1 + 0.2 != 0.3` in binary floating point, and errors compound across a day of transactions. That leaves `Decimal` or integer-minor-units.

Most currencies force integer-minor-units (cents, pence), with all the ×100 arithmetic that implies. **IDR is unusual: it has no circulating subunit.** The rupiah's sen hasn't been used since the 1950s. So the smallest unit *is* the rupiah, and `Int` needs no scaling at all — `12000` means Rp 12.000, exactly, with no conversion anywhere.

`Decimal` would also be correct, but it's a struct with arithmetic that can throw and formatting that needs care, in exchange for precision you cannot use.

**What it costs.** If this app ever handles a currency with cents, every money field changes meaning. That's why the naming convention is `priceRp`, not `price` — the unit is in the name, so the change would be a compiler error rather than a silent factor-of-100 bug.

**How you'd know this was wrong.** The day someone asks to price something at Rp 500,50.

---

## 8. Why an append-only stock ledger

**Decision.** `StockMovement` rows are the truth. `Product.stockQty` is a cache.

**What it's for.** Answering *why*, not just *what*.

**Why it must be so.** A counter answers "how many do I have." A ledger answers "how many, and how did it get that way." The second question is the one the owner actually asks, always in the form "my stock says 12 and I count 9."

There's also an internal-consistency argument, which is how this decision was actually reached. D-06 already required that a void write a **reversal record** rather than delete the sale. If stock were a bare counter, the void would silently do `+2` with no trace — money would have an audit trail and stock wouldn't. **A system where half the records are auditable is a system nobody trusts**, because you can't tell which half you're looking at.

**What it costs.** One extra entity, and R-03-11's atomicity requirement: movement and cache update in one transaction. Roughly half a day.

**How you'd know this was wrong.** If, after months, nobody ever opens the movement history. Watch for that — it's the honest test.

---

## 9. Why `SaleLine` snapshots name and price

**Decision.** Each line copies `nameSnapshot` and `unitPriceRp` at tender. History never reads live product data.

**What it's for.** Making past sales immutable in fact, not just by convention.

**Why it must be so.** This is the load-bearing rule of the whole system. Without it: the owner raises Chitato from 12.000 to 15.000, and **last month's revenue changes.** Not a display glitch — the actual reported total for a closed period silently increases, because the join reads the current price.

The general principle is worth carrying to every system you build: **a record of a transaction must contain everything needed to reproduce it.** A foreign key is not a fact; it's a pointer to something that can change underneath you. `SaleLine` stores facts.

**What it costs.** Denormalisation. Product names are duplicated across thousands of rows, and renaming a product doesn't retroactively tidy history — which is the point, not a bug.

**How you'd know this was wrong.** If the owner ever complains that a typo in a product name persists in old receipts. That complaint is the system working correctly, and the answer is "yes, because that's what the receipt said."

---

## 10. Why `productID` is a weak `UUID?`

**Decision.** `SaleLine.productID` is a plain `UUID?` — deliberately **not** a SwiftData relationship.

**What it's for.** Making it structurally impossible for a catalogue change to damage financial history.

**Why it must be so.** A relationship needs a delete rule, and every option is bad:

| Delete rule | What happens when a product is deleted |
|---|---|
| `.cascade` | **Sale lines are destroyed.** Revenue history disappears. |
| `.nullify` | The line survives but loses its link — which is what a plain `UUID?` already gives you, with less machinery |
| `.deny` | Deleting a sold product becomes impossible. Also forbidden by CloudKit. |

Using a weak ID removes the decision entirely. There is no delete rule, so there is no wrong one, and no future refactor can accidentally introduce a cascade into your sales table.

This generalises: **when every option for a configuration is wrong, delete the configuration.** The safest setting is the one that doesn't exist.

**What it costs.** No referential integrity and no automatic joins — you resolve a product by ID manually when you need it. Which, thanks to §9, is almost never.

**How you'd know this was wrong.** If you find yourself constantly hand-resolving `productID` to get at product data in history screens. You shouldn't be — that's what the snapshots are for.

---

## 11. Why soft delete

**Decision.** `deletedAt: Date?`. Nothing is ever hard-deleted.

**What it's for.** Two unrelated needs that happen to share a mechanism: CloudKit deletions don't propagate reliably, and history must survive catalogue changes.

**Why it must be so.** Once you accept §9 and §10, hard delete is *almost* safe — snapshots mean history survives. But "almost safe" plus "sync deletes are unreliable" is enough. The cost is one nullable column.

The subtlety worth understanding is that **soft delete changes the meaning of every query in the system.** R-03-1 says barcodes are unique among *non-deleted* products. So a deleted product's barcode can be reused by a new one, and the store then contains that barcode twice. That's correct, and it's an edge case you must handle deliberately (module 03 §8), not discover.

**What it costs.** Every fetch must filter `deletedAt == nil`. Forget once and deleted products reappear. This is exactly the kind of easily-forgotten filter that justifies the repository layer.

**How you'd know this was wrong.** If deleted rows accumulate to the point of affecting performance. At this scale, they won't.

---

## 12. Why one `save()` per operation

**Decision.** `SaleService.complete` inserts the sale, its lines, and every movement, then saves exactly once.

**What it's for.** Atomicity. All of it happens, or none of it does.

**Why it must be so.** With multiple saves, a failure between them leaves a sale with no stock movements — money recorded, stock untouched. Nothing in the system detects this, and no report reveals it. It just quietly becomes wrong, forever.

**This is the worst class of bug this system can produce**, which is why AC-04-16 is the test you write *first*, before the commit path exists. Writing the test first is not ceremony here; it's the only way to be sure the failure path was ever exercised, because the happy path never touches it.

**What it costs.** Services get longer — you assemble everything, then save. You can't save incrementally for a progress bar. Neither matters here.

**How you'd know this was wrong.** If a single operation genuinely needs to be resumable across app launches. At that point you'd need an outbox, which foundations §8 explicitly forbids at this scale.

---

## 13. Why the cart lives in memory

**Decision.** `SaleDraft` is a ViewModel struct. Nothing persists before tender.

**What it's for.** Making tender the single pivot event, and keeping the pre-tender cart completely free to manipulate.

**Why it must be so.** The alternative is a persisted `Sale` with status `draft`, and it drags in: partially-written sales in the database, orphan cleanup, "what happens to a draft from three days ago", and drafts polluting every query that forgets to filter status.

**The cost is real and accepted:** a crash or force-quit mid-cart loses the cart. That's a genuine downside, chosen because at ~5 items per cart, re-scanning is 10 seconds, while draft lifecycle management is permanent complexity in every sales query you ever write.

Note the shape of this trade: **a rare, cheap, recoverable failure beats a permanent structural cost.** That's a trade worth recognising in general.

**How you'd know this was wrong.** If carts get big — 30+ items — or if crashes turn out to be common. Then drafts start earning their complexity.

---

## 14. Why `nil` is not `0`

**Decision.** A QRIS sale stores `cashReceivedRp = nil` and `changeRp = nil`. Never `0`.

**What it's for.** Keeping "not applicable" distinguishable from "the amount was zero."

**Why it must be so.** Both are legitimate states and they mean different things:

- `changeRp = 0` — a cash sale where the customer paid exactly. Change was due; it was nothing.
- `changeRp = nil` — a QRIS sale. Change is not a concept here.

Store both as `0` and you can no longer answer "how many cash sales were paid exactly?" — the QRIS sales are mixed in. The information isn't hidden, it's **destroyed**, and no later query can recover it.

Swift's optionals make this free. A language without them pushes you toward sentinel values (`-1`, `0`, `""`) and this bug class becomes routine. Optionals are the type system offering to track "this may not exist" for you; conflating nil with zero is declining the offer.

**What it costs.** Unwrapping at every read site. Which is the type system asking you a question you should have an answer to.

**How you'd know this was wrong.** You wouldn't — this one has no realistic downside.

---

## 15. Why zero stock warns instead of blocking

**Decision.** Selling below zero stock is allowed. Stock goes negative and is shown in red.

**What it's for.** Not letting the software contradict physical reality.

**Why it must be so.** The customer is holding the item. It exists. A dialog saying "cannot sell, out of stock" is the software claiming otherwise — and the operator's only path forward is to abandon the sale or fake a stock adjustment mid-queue. Both are worse than an inaccurate number.

And negative stock is not an error state, it's **information**: it means goods left the shelf without being recorded. That's a real event the owner needs to know about, and clamping to zero would erase the evidence.

**What it costs.** Stock numbers can be wrong in a visible way. Which is better than being wrong in an invisible way.

**How you'd know this was wrong.** In a business where negative stock indicates fraud rather than sloppy record-keeping, blocking would be right. Not this business.

---

## 16. Why sale numbers have no gaps

**Decision.** `{YYYYMMDD}-{NNN}`, sequential per Jakarta day. Voided sales keep and consume their number.

**What it's for.** Making the receipt sequence self-auditing.

**Why it must be so.** If a void freed its number for reuse, `-007` could refer to two different sales. If a void removed the number entirely, the sequence would gap — and **a gap is indistinguishable from a deleted sale.** Anyone looking at the books can't tell "this was voided" from "someone removed this."

Keeping the number and marking the status makes the record complete: the sale happened, then it was cancelled, and both facts are visible.

**What it costs.** Numbering must count existing rows for the day, which is a query on every tender. Trivial at 50 sales/day, and it would need rethinking at 50/second.

**How you'd know this was wrong.** Under concurrency — two devices numbering the same day — this scheme breaks immediately. It's correct precisely because D-03 says one device. If D-03 changes, this must change with it. **Note that dependency**: it's the kind of coupling between decisions that causes bugs when one is revisited alone.

---

## 17. Why every day boundary is Asia/Jakarta

**Decision.** All grouping in WIB (UTC+7), regardless of device timezone.

**What it's for.** "Today's sales" meaning the same thing every time it's asked.

**Why it must be so.** Concretely: sales at 23:58 and 00:03 WIB on consecutive days are 16:58 and 17:03 UTC **on the same UTC day**. Group by UTC and yesterday's last sale lands in today's total. Group by device timezone and the totals change when the owner travels.

A trading day is a business concept, not a technical one, and it must be anchored to the business's location.

**What it costs.** One helper (`JakartaDay`) and the discipline that nothing else computes day boundaries. AC-05-5 runs the test suite with the device timezone set to UTC specifically to catch violations.

**How you'd know this was wrong.** Multiple branches in different timezones. Then the boundary belongs to the branch, not the app.

---

## 18. Why contacts are stored twice

**Decision.** Both `contactID` and a `contactName` snapshot. Always both.

**What it's for.** Surviving the address book changing underneath you.

**Why it must be so.** `CNContact.identifier` is not a stable key you own — it belongs to a database another app controls. It changes on merge and vanishes on delete. Store only the ID and every deleted contact turns a supplier field into a blank row, retroactively, in records that were correct when written.

The snapshot means the worst case degrades to *plain text that's slightly out of date*, instead of *missing data*. And per R-02-2 the snapshot is never refreshed — same principle as §9. A record describes what was true when it was written.

**What it costs.** Two columns instead of one, and stale names after a rename.

**How you'd know this was wrong.** If users expect renames to propagate. They'd be asking for something that would also silently rewrite history, so the answer is the explanation, not the feature.

---

## 19. Why there is no auth

**Decision.** One operator, no login, no roles, no permission checks.

**What it's for.** Not building a module the business doesn't need yet.

**Why it must be so.** Owner and cashier are the same person. Auth would mean: a user entity, session handling, a permission matrix, a permission check at every mutation, and a role dimension in every test. That's a module, and it protects against a threat that doesn't exist.

**What it costs — and this needs saying plainly.** The system has **no fraud controls**. Anyone with the unlocked phone can void a sale, change a price, or adjust stock away. The `voidReason` field is the only deterrent, and it's a text box, not a control.

**How you'd know this was wrong.** The day a second person works the counter. Note that this is not a gradual pressure — it's a step change, and it's why foundations §3 states the gap explicitly instead of leaving it to be discovered. **The point of documenting an omission is that "we didn't need it" and "we forgot" look identical in code six months later.**

---

## 20. Why no event bus

**Decision.** Modules call each other's exported service interfaces directly.

**What it's for.** Not adding indirection that buys nothing.

**Why it must be so.** An event bus decouples emitter from consumers, which pays off when consumers are numerous, unknown, or optional. Here there are four cross-module calls, all known, all required. Routing `StockService.record` through an event would make the call harder to trace, harder to test, and impossible to make atomic — and §12 requires it to be atomic, inside the same save. **An event bus would actively break the most important guarantee in the system.**

**What it costs.** Modules know each other's interfaces. At four call sites, that's a feature.

**How you'd know this was wrong.** When one action needs to trigger three unrelated side effects and the list keeps growing.

---

## 21. Why one Xcode target

**Decision.** One app target. Module boundaries are convention, enforced by `grep` in the audit.

**What it's for.** Not spending a day on build configuration in a ten-day project.

**Why it must be so.** Real enforcement means local SPM packages with explicit dependencies — genuinely better, and it makes `SaleService` writing `stockQty` a compile error rather than a review finding. It also costs a day of setup and friction on every file added.

The mitigation is targeted: **AC-04-17 greps `Features/Sale/` for `stockQty`.** That's the one violation that would actually matter, caught for one line in `/verify-module`. This is a good pattern in general — when full enforcement is too expensive, enforce the specific case that hurts.

**What it costs.** Discipline substitutes for the compiler, and discipline degrades with team size and fatigue.

**How you'd know this was wrong.** A second developer, or the first time the audit catches a boundary violation that got committed.

---

## 22. Why zero third-party dependencies

**Decision.** No SPM packages. Apple frameworks only.

**What it's for.** Your ten days going into Swift rather than into other people's abstractions.

**Why it must be so.** Every dependency is a thing you learn *instead of* the thing underneath it. Add a networking library and you learn its API rather than `URLSession`. Add a DI framework and you learn its container rather than constructor injection. For a production app under deadline that's often the right trade. **For a learning project it is precisely backwards** — the goal is the fundamentals, and a dependency's whole value proposition is hiding them.

**What it costs.** You write some things by hand — `AppContainer`, the `DataScannerViewController` wrapper — that a package would have given you.

**How you'd know this was wrong.** If you spend more than half a day on infrastructure that isn't teaching you anything. Charting is the likely candidate; use Swift Charts (Apple's) if it comes up.

---

## 23. The meta-lesson

Twenty-two decisions are documented here. **Most decisions in a project do not deserve this.** The ones that did share a property worth naming, because recognising it is the transferable skill:

**They are expensive to reverse.**

| Cheap to reverse — decide fast, don't document | Expensive to reverse — decide slowly, document |
|---|---|
| Button placement, colours, copy | Schema shape (§6) |
| Which view holds which subview | What a record snapshots (§9) |
| Function names, file organisation | What is a relationship vs. a plain ID (§10) |
| Sort order of a list | Whether history is append-only (§8) |
| | Whether an operation is atomic (§12) |

The pattern: **decisions with data on top of them are the expensive ones.** Code can be rewritten in an afternoon. A schema with 18,000 sales in it cannot, because every change is also a migration, and every migration can lose data.

That's the practical answer to "how do I know which decisions matter." Not "is this important" — everything feels important — but: *if I get this wrong and discover it in three months, what does the fix cost?* If the answer is "an afternoon," decide quickly and move. If it's "a migration and a risk of data loss," stop and write it down.

Two decisions in this document were **reversed during the interview**, and both illustrate the point. `@Attribute(.unique)` on barcode (worked locally, would have failed silently under CloudKit) and the bare stock counter (would have contradicted the audit trail the void decision demanded). Both were caught before any code existed. Both would have been schema migrations if caught later.

That's what the interview was for.

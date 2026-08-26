# Swift Fundamentals

> A reference for the Act phase. Every section ends with **→ In your POS**, naming exactly where the concept appears, so you learn it against something real rather than in the abstract.
>
> Read §5 (state ownership) and §6 (concurrency) properly. They are where almost all SwiftUI confusion actually lives, and they are the two areas where old tutorials will actively mislead you.

---

## Contents

1. [Value types vs reference types](#1-value-types-vs-reference-types)
2. [Optionals](#2-optionals)
3. [Protocols and dependency injection](#3-protocols-and-dependency-injection)
4. [Error handling](#4-error-handling)
5. [State ownership in SwiftUI](#5-state-ownership-in-swiftui) ← the big one
6. [Concurrency](#6-concurrency) ← the other big one
7. [SwiftData specifics](#7-swiftdata-specifics)
8. [Memory and ARC](#8-memory-and-arc)
9. [Generics, `some`, and `any`](#9-generics-some-and-any)
10. [Access control](#10-access-control)
11. [Testing](#11-testing)
12. [Idioms worth internalising](#12-idioms-worth-internalising)
13. [A 10-day learning order](#13-a-10-day-learning-order)

---

## 1. Value types vs reference types

The single most consequential distinction in Swift.

| | `struct` / `enum` | `class` / `actor` |
|---|---|---|
| Semantics | **Copied** on assign and pass | **Shared** — a reference is copied, not the object |
| Identity | None. Two structs with equal fields are interchangeable. | Has identity. `===` asks "the same object?" |
| Mutation | Needs `var`; methods that mutate need `mutating` | Mutable through a `let` reference |
| Inheritance | No | Yes (classes) |
| Thread safety | Easy — nobody shares it | Hard — everyone might |

**The mental model:** a struct is a *value*, like the number 5. A class is a *thing*, like a person. There is only one of a given person; there are many copies of 5.

```swift
struct Point { var x = 0 }
var a = Point(); var b = a; b.x = 10
// a.x == 0   — b got a copy

class Box { var x = 0 }
let c = Box(); let d = c; d.x = 10
// c.x == 10  — c and d are the same Box (and note: `let` didn't stop it)
```

That last line surprises everyone. `let` on a class means *the reference* can't be reassigned — it says nothing about the object's contents.

**Default to `struct`.** Reach for `class` when you need identity, shared mutable state, or a framework demands it (`@Observable` ViewModels, `@Model` types).

`enum` is Swift's underrated feature — a closed set of cases the compiler forces you to handle exhaustively:

```swift
enum StockReason: String, CaseIterable {
    case opening, restock, sale, void, adjustment
}
```

Add a sixth case and every `switch` that doesn't handle it stops compiling. That's the compiler doing code review.

**→ In your POS.** `ContactRef`, `DraftLine`, `DaySummary`, `Rp` are structs — pure values, trivially testable. `Product`, `Sale` are classes because `@Model` requires it and because two `Product`s with the same name are genuinely different products. `StockReason`, `PaymentMethod`, `SaleStatus`, `BarcodeKind`, `POSError` are enums.

---

## 2. Optionals

`T?` means "a `T`, or nothing." It is not a null pointer — it's `Optional<T>`, an enum with `.some(T)` and `.none`, and the compiler will not let you use the value without handling both.

**Five ways to unwrap, in rough order of preference:**

```swift
// 1. if let — do something only when present
if let barcode = product.barcode { print(barcode) }

// 2. guard let — bail out early, keep the happy path unindented
guard let product = try repo.findBy(barcode: code) else {
    throw POSError.productNotFound
}
// `product` is non-optional for the rest of the function

// 3. ?? — supply a default
let name = product.supplierName ?? "Tanpa supplier"

// 4. optional chaining — call through, get nil if any link is nil
let count = sale.lines?.count ?? 0

// 5. ! — force unwrap. Crashes if nil.
let n = product.barcode!    // don't
```

**`guard let` is the workhorse.** It keeps the error path at the top and the real logic unindented, which matters more than it sounds in a service with six validations.

**Force-unwrap `!` is a promise you're making to the compiler.** In this project: outlaw it in services and models. It's tolerable in tests where a crash *is* the failure report.

**The lesson worth carrying:** an optional is the type system offering to track "this might not exist" on your behalf. Reaching for a sentinel — `-1`, `0`, `""` — is declining that offer and hand-rolling a worse version.

**→ In your POS.** `Product.barcode` is `String?` because loose goods have none. `Sale.changeRp` is `Int?` because QRIS has no change — and DESIGN_RATIONALE §14 explains why storing `0` there would destroy information you can never recover. `guard let` gates every service method that takes an ID.

---

## 3. Protocols and dependency injection

A protocol is a contract: "whatever conforms to this can do these things." Swift leans on protocols where other languages lean on inheritance.

```swift
protocol StockServicing {
    func record(product: Product, delta: Int,
                reason: StockReason, note: String?, saleID: UUID?) throws
    func recompute(product: Product) throws -> Int
}

struct StockService: StockServicing {
    let repo: StockMovementRepository        // a protocol too
    func record(...) throws { /* real work */ }
}
```

**Dependency injection**, stripped of mystique, is one sentence: *give an object its collaborators instead of letting it construct them.*

```swift
// ❌ constructs its own — untestable, always hits disk
struct SaleService {
    let repo = SwiftDataSaleRepository()
}

// ✅ receives it — a test can pass a fake
struct SaleService {
    let repo: SaleRepository          // protocol
    let stock: StockServicing
}
```

You don't need a DI framework for this. A single composition root — `AppContainer` — builds the real objects once at launch, and tests build fakes.

```swift
@MainActor
final class AppContainer {
    let stock: StockServicing
    let catalogue: CatalogueServicing

    init(context: ModelContext) {
        let productRepo = SwiftDataProductRepository(context: context)
        self.stock = StockService(repo: SwiftDataStockMovementRepository(context: context))
        self.catalogue = CatalogueService(repo: productRepo, stock: stock)
    }
}
```

**Protocol extensions** give default implementations, which is how Swift shares behaviour without inheritance:

```swift
extension StockServicing {
    func restock(_ product: Product, qty: Int) throws {
        try record(product: product, delta: qty, reason: .restock, note: nil, saleID: nil)
    }
}
```

**→ In your POS.** Every service and repository is a protocol plus a conformance. This is what makes `SaleServiceTests` run in milliseconds with no disk, and it's what makes the SwiftData→GRDB swap in ADR-01 possible at all.

---

## 4. Error handling

Swift has three mechanisms. Know when each applies.

**`throws` — recoverable failure the caller must handle.**

```swift
func complete(...) throws -> Sale {
    guard !lines.isEmpty else { throw POSError.emptyCart }
    guard cash >= total else {
        throw POSError.insufficientCash(shortfallRp: total - cash)
    }
    ...
}

do    { let sale = try service.complete(...) }
catch { errorMessage = (error as? POSError)?.message ?? "Terjadi kesalahan" }
```

Note `insufficientCash(shortfallRp:)` — **an error carrying data**. That's an enum with an associated value, and it lets the UI say "Kurang Rp 4.000" instead of "invalid amount." Errors that carry the specific thing that went wrong are the difference between a helpful app and a frustrating one.

**The three `try`s:**

| Form | Behaviour | Use |
|---|---|---|
| `try` | Propagates the error | Almost always |
| `try?` | Converts to `nil`, discarding the error | **Banned on write paths.** A swallowed save failure is a lost sale. |
| `try!` | Crashes | Tests only |

**`Result<Success, Failure>`** — an error stored as a value rather than thrown. Rarely needed now that async/await supports `throws`; you'll see it in older code.

**Fatal errors** — `fatalError()`, `precondition()` — are for programmer mistakes, not user situations. "The container failed to build" is fatal. "The cash is short" is not.

**→ In your POS.** One `POSError` enum for the whole app (foundations §7). Repositories may throw SwiftData errors; services wrap them into `.persistenceFailed`. Every case has an Indonesian message — an error the operator can't read is not handled, just logged.

---

## 5. State ownership in SwiftUI

**This is where most SwiftUI confusion lives.** The question is never "which property wrapper" — it's **who owns this state, and who is merely reading it.**

### The modern set (iOS 17+)

| Wrapper | Meaning | Owns the state? |
|---|---|---|
| `@State` | This view owns it | **Yes** |
| `@Binding` | Read/write access to state owned by an ancestor | No |
| `@Observable` (macro on a class) | This object publishes changes | n/a — it's the model |
| `@Bindable` | Make bindings into an `@Observable` object's properties | No |
| `@Environment` | Pull a value injected by an ancestor | No |
| `@AppStorage` | Backed by `UserDefaults` | Yes, but on disk |

### What the legacy tutorials will show you

| Old (pre-iOS 17) | Modern replacement |
|---|---|
| `ObservableObject` + `@Published` | `@Observable` macro |
| `@StateObject` | `@State` |
| `@ObservedObject` | plain `let` property, or `@Bindable` |
| `@EnvironmentObject` | `@Environment` |

**You will hit this constantly.** Most tutorials online predate iOS 17. If you see `@Published`, you're reading old material — the concepts still apply, the spelling has changed.

### `@Observable` — what the macro actually does

```swift
@Observable
final class CartViewModel {
    var lines: [DraftLine] = []
    var errorMessage: String?

    var totalRp: Int { lines.reduce(0) { $0 + $1.lineTotalRp } }
}
```

The macro rewrites each stored property so reads and writes are tracked. A SwiftUI view then re-renders **only when a property it actually read in `body` changes.**

That last part is the real upgrade over `ObservableObject`. With `@Published`, any change fired `objectWillChange` and re-rendered every observing view. With `@Observable`, a view that reads only `totalRp` doesn't re-render when `errorMessage` changes. Free performance, no annotation required.

### The ownership rules, concretely

```swift
struct CartView: View {
    // OWNS the ViewModel. @State keeps it alive across re-renders.
    @State private var vm: CartViewModel

    var body: some View {
        VStack {
            ForEach(vm.lines) { line in CartLineRow(line: line) }
            Text(Rp.format(vm.totalRp))
            TenderSheet(vm: vm)          // pass it down — no wrapper needed to READ
        }
    }
}

struct QtyStepper: View {
    @Binding var qty: Int                // BORROWS write access to an Int
    var body: some View { Stepper("\(qty)", value: $qty, in: 1...99) }
}

struct TenderSheet: View {
    @Bindable var vm: CartViewModel      // need $vm.cashReceived for a TextField
    var body: some View {
        TextField("Tunai", value: $vm.cashReceivedRp, format: .number)
    }
}
```

**Three rules that resolve nearly every question:**

1. **`@State` for what this view owns.** With `@Observable`, `@State` is correct for objects too — `@StateObject` is gone.
2. **Passing down to *read*? No wrapper.** A plain `let` property is enough; observation still works.
3. **Passing down to *write*? `@Binding` for values, `@Bindable` for `@Observable` objects.**

### The `$` sigil

`$vm.name` is a **projected value** — for `@State` and `@Binding`, that's a `Binding<T>`: a read-write handle, not a copy. `TextField` needs one because it must write back.

### Why `@State` and not a plain `var`

SwiftUI views are **structs that get destroyed and recreated constantly** — every parent re-render makes a new one. A plain `var` is reinitialised each time. `@State` stores the value *outside* the struct, in storage SwiftUI keeps alive across those recreations.

That's the whole reason property wrappers exist here: **a view is a description of UI, not the UI itself.** State can't live in a description.

### `@Environment`

```swift
// inject once, at the root
RootTabView().environment(appContainer)

// read anywhere below
struct ProductListView: View {
    @Environment(AppContainer.self) private var container
}
```

Good for genuinely global things — the DI container, `\.colorScheme`, `\.dismiss`. Bad as a general communication channel: it's invisible coupling, and a missing environment value is a **runtime** crash, not a compile error.

**→ In your POS.** Each screen has one `@Observable` ViewModel held by `@State`. `AppContainer` comes through `@Environment`. `@Bindable` appears in the tender sheet and product form, where `TextField` needs two-way bindings. `@Query` is banned — see DESIGN_RATIONALE §4.

---

## 6. Concurrency

### Threads vs actors

A **thread** is an OS execution context. An **actor** is a Swift construct guaranteeing that only one task touches its state at a time. `@MainActor` is a *global actor* pinned to the main thread — the only place UI work is legal.

`@MainActor` doesn't mean "run this on a background thread and hop back." It means **this code is isolated to the main actor**, and the compiler enforces it. Calling it from elsewhere requires `await`.

```swift
@MainActor
final class CartViewModel { ... }     // whole type isolated

final class Thing {
    @MainActor func updateUI() { }    // one method isolated
}
```

### `async` / `await`

```swift
func scan() async throws -> String? { ... }

Task {
    let code = try await scanner.scan()
}
```

**`await` marks a *suspension point*, not a thread switch.** It means "this function may pause here, and other work may run in the meantime." When it resumes, it resumes in the same isolation it started in.

**The single most common misconception:** `await` does **not** move work off the main thread. A slow synchronous function called inside an `async` method on `@MainActor` still blocks the UI. Getting off the main actor is a separate, deliberate act.

### `Task`

```swift
Task { }            // inherits the current actor context — MainActor if started from a view
Task.detached { }   // inherits NOTHING. Almost always the wrong tool.
```

`Task { }` in a `@MainActor` context stays on the main actor. That's usually what you want, and it's why `Task.detached` should raise an eyebrow in review.

### `actor`

```swift
actor Counter {
    private var value = 0
    func increment() { value += 1 }   // serialized automatically
}
let c = Counter()
await c.increment()                    // await required from outside
```

An actor is a class whose state cannot be touched concurrently. You will likely not need one in this project — that's a good sign, not a gap.

### `Sendable`

`Sendable` marks a type as safe to pass across isolation boundaries. Value types of `Sendable` members are automatically `Sendable`. Classes generally are not, unless immutable or internally synchronised.

Under Swift 6 strict concurrency, passing a non-`Sendable` type across an actor boundary is a **compile error**. This is the source of most Swift 6 migration pain, and it is the compiler finding real data races.

### Swift 6.2 changes the default — use it

< cite index="152-1">Default Actor Isolation in Swift 6.2 lets you run code on the `@MainActor` by default</cite>, and < cite index="155-1">both `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are on by default for new Xcode projects.</cite> < cite index="151-1">With both enabled, essentially all your code runs on MainActor unless you explicitly say otherwise.</cite>

< cite index="153-1">For app targets this makes a lot of sense: you write simpler code and introduce concurrency only where you actually need it.</cite> < cite index="155-1">`@concurrent` is the escape hatch — mark a function `@concurrent` to push heavy CPU work onto a background thread, deliberately and visibly.</cite>

< cite index="155-1">The model inverts the burden: instead of proving every line is safe to run off-main, you keep everything on-main and prove the few places you leave.</cite>

**For this project: leave both settings on.** Your app is a single-user till. Everything is main-actor. The one place you cross a boundary is the scanner's camera callback, and the framework handles that. You get Swift 6 data-race safety without spending your ten days fighting `Sendable` errors — which would teach you the migration, not the language.

**→ In your POS.** `AppContainer` and the ViewModels are `@MainActor`. `ModelContext` is not `Sendable`, so anything touching it is main-actor too. `ScannerService.scan()` is `async` because presenting a camera and awaiting a result is inherently asynchronous. No `actor`, no `Task.detached`, no manual `DispatchQueue` — if you find yourself reaching for one, stop and ask why.

---

## 7. SwiftData specifics

### `@Model`

```swift
@Model
final class Product {
    var id: UUID = UUID()
    var name: String = ""
    var priceRp: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \StockMovement.product)
    var movements: [StockMovement]? = []
}
```

The macro makes the class conform to `PersistentModel` **and** `Observable` — so a `@Model` object drives SwiftUI updates for free, with no extra annotation.

`final` is required. Persistent models can't be subclassed.

### Container and context

- **`ModelContainer`** — the store. One per app, built at launch.
- **`ModelContext`** — the working scratchpad. Tracks changes; `save()` commits them.

`ModelContext` is **not `Sendable`** — it must not cross actor boundaries. That constraint is why so much of this app is `@MainActor`, and it's a good example of a framework limitation propagating into architecture.

### Fetching

```swift
let descriptor = FetchDescriptor<Product>(
    predicate: #Predicate { $0.deletedAt == nil },
    sortBy: [SortDescriptor(\.name)]
)
let products = try context.fetch(descriptor)
```

`#Predicate` is a macro compiled into a store query — it is not an arbitrary Swift closure, and it supports a limited subset of expressions. Hitting that ceiling is the moment DESIGN_RATIONALE §5 says to consider GRDB.

### Autosave

SwiftData autosaves periodically. **Do not rely on it.** Call `save()` explicitly at the end of each business operation — that's what makes the atomicity guarantee in DESIGN_RATIONALE §12 real rather than probabilistic.

### The CloudKit constraints

Covered in DESIGN_RATIONALE §6, and mandatory here from day one. In short: every property optional or defaulted, no `@Attribute(.unique)`, every relationship optional with an explicit inverse, no `.deny` delete rules, soft deletes only.

**→ In your POS.** Four `@Model` types. All fetching in repositories, never views. One explicit `save()` per business operation.

---

## 8. Memory and ARC

Swift uses **Automatic Reference Counting**: an object lives while at least one strong reference points at it. No garbage collector, no pauses — but cycles leak.

```swift
class Parent { var child: Child? }
class Child  { var parent: Parent? }     // ⚠️ strong cycle — neither is ever freed
```

**The fix:** make one side non-owning.

| | Meaning | Use when |
|---|---|---|
| `strong` (default) | Keeps the object alive | Ownership |
| `weak` | Doesn't keep alive; becomes `nil` when freed. Must be `var` and optional. | The reference may outlive the referent |
| `unowned` | Doesn't keep alive; **crashes** if accessed after free | You're certain the referent outlives you |

**Closures capture strongly by default**, which is the usual source of leaks:

```swift
// ⚠️ vm holds the closure, closure holds vm
service.onComplete = { self.reload() }

// ✅
service.onComplete = { [weak self] in self?.reload() }
```

`[weak self]` is a **capture list**. In SwiftUI's declarative style this comes up less than in UIKit, but it still bites in long-lived closures and async callbacks.

**→ In your POS.** SwiftData manages the `Product` ↔ `StockMovement` cycle for you — that's what the explicit `inverse:` is partly for. Watch for capture-list needs in the scanner callback and any escaping closure a ViewModel stores. And note DESIGN_RATIONALE §10: `SaleLine.productID` being a plain `UUID` rather than a relationship means there is no reference and therefore no cycle to reason about at all — a structural fix beating a memory-management fix.

---

## 9. Generics, `some`, and `any`

```swift
func first<T>(of items: [T]) -> T? { items.first }
```

`T` is a placeholder resolved at compile time — one implementation, full type safety.

**`some` vs `any`** — the distinction that confuses everyone:

```swift
var body: some View        // ONE specific type, the compiler knows which. Opaque.
let s: any StockServicing  // ANY conforming type, resolved at runtime. Existential.
```

| | `some P` | `any P` |
|---|---|---|
| Type | One concrete type, hidden from you | Could be any conformer |
| Dispatch | Static — fast | Dynamic — a pointer hop |
| Can store different types in the same variable? | No | Yes |

`some View` is why SwiftUI works: `body` returns a deeply nested generic type that would be unreadable to write out, so the compiler infers it and hides it — with no runtime cost.

Use `some` by default; reach for `any` only when you genuinely need heterogeneity.

**→ In your POS.** `some View` everywhere in view bodies. Services stored as protocol types in `AppContainer` — `let stock: any StockServicing`, or use generics if you want the extra performance you almost certainly don't need. Generics are otherwise light in this project; that's fine.

---

## 10. Access control

| Level | Visible to |
|---|---|
| `private` | The enclosing declaration and its extensions in the same file |
| `fileprivate` | The whole file |
| `internal` (default) | The whole module |
| `public` | Other modules |
| `open` | Other modules, and subclassable |

With one Xcode target, `internal` and `public` are the same thing — which is exactly why the module boundaries in this project are convention rather than compiler-enforced (DESIGN_RATIONALE §21).

**Still use `private` aggressively.** It documents intent and prevents accidental coupling inside a file:

```swift
@Observable
final class CartViewModel {
    private(set) var lines: [DraftLine] = []   // readable outside, writable only inside
    private let service: SaleServicing
}
```

`private(set)` is the underused one — it makes state readable but not mutable from outside, which is exactly right for a ViewModel's published data.

**→ In your POS.** ViewModel dependencies `private`. Published state `private(set)`. Repository internals `private`.

---

## 11. Testing

Swift Testing is the modern framework — macros instead of XCTest's subclass-and-prefix conventions.

```swift
import Testing

@Test func rpFormatsThousands() {
    #expect(Rp.format(12000) == "Rp 12.000")
}

@Test func insufficientCashThrowsWithShortfall() throws {
    let service = SaleService(repo: InMemorySaleRepository(), stock: FakeStockService())
    #expect(throws: POSError.insufficientCash(shortfallRp: 4000)) {
        try service.complete(lines: [line29000], method: .cash, cashReceivedRp: 25000, customer: nil)
    }
}

@Test(arguments: [
    ("8992775311011", BarcodeKind.gtin),
    ("2011234501234", BarcodeKind.internalCode),
])
func classifiesBarcodes(raw: String, expected: BarcodeKind) {
    #expect(BarcodeKind.of(raw) == expected)
}
```

- `#expect` — asserts and continues.
- `#require` — asserts and stops the test if it fails (use to unwrap).
- `@Test(arguments:)` — parameterised, one row per case in the report.

**What to test here:** services and ViewModels — the layers holding the rules. **Not** views. If a rule is hard to test, that usually means it's in the wrong layer.

**→ In your POS.** One test per numbered rule, named `test_R0403_snapshotsPriceAtTender`. The rule ID in the name is what lets `/verify-module` map tests to rules mechanically. `AC-04-16` — a forced failure inside `complete` leaves zero rows — is the one to write first.

---

## 12. Idioms worth internalising

**Extensions** — add behaviour to any type, including Apple's:

```swift
extension Int {
    var asRupiah: String { Rp.format(self) }
}
```

Powerful and easy to abuse. Keep them to genuinely general behaviour; a domain rule hiding in an extension on `Int` is a rule nobody will find.

**Computed properties over stored, when derivable:**

```swift
var lineTotalRp: Int { unitPriceRp * qty }    // can never disagree with its inputs
```

Note that `SaleLine.lineTotalRp` is nonetheless **stored** in the schema — deliberately, because a persisted sale must record what was actually charged, not recompute it later. That's the §9 snapshot principle overriding the general preference. **Knowing when a principle is outranked is the actual skill.**

**`guard` for early exit** — keeps the happy path unindented.

**Trailing closures:**

```swift
Button("Bayar") { vm.tender() }
```

**`map` / `filter` / `reduce`:**

```swift
let total = lines.reduce(0) { $0 + $1.lineTotalRp }
let active = products.filter { $0.deletedAt == nil }
```

**`switch` must be exhaustive** — this is a feature. Avoid `default:` on your own enums; it silently absorbs new cases instead of making you handle them.

**String interpolation with formatting:**

```swift
Text("\(sale.createdAt, format: .dateTime.hour().minute())")
```

---

## 13. A 10-day learning order

Fundamentals attach to code you've written. Don't front-load theory.

| Day | Build | Learn alongside |
|---|---|---|
| 1 | Module 01 | §1 value/reference, §2 optionals, §10 access control |
| 2 | Module 01 tests + 02 | §3 protocols and DI, §11 testing, §4 error handling |
| 3–4 | Module 03 | §7 SwiftData, §5 state ownership, §8 ARC |
| 5–6 | Module 04 | §5 again (properly, it's the hard one), §6 concurrency |
| 7 | Module 05 | §12 idioms, §9 `some` vs `any` |
| 8 | Golden path + fixes | Re-read DESIGN_RATIONALE — you'll now disagree with parts of it |
| 9 | Write the three ADRs | The actual learning evidence |
| 10 | Polish + retro | Which decisions would you now make differently? |

**On day 9, write ADR-02 (repository-enforced uniqueness) first.** By then you'll have felt the constraint in real code — you'll have written the `findBy(barcode:)` check and wondered why it isn't just a schema attribute. An ADR written *after* the friction is a real argument. One written before is a guess.

**And on day 10, write down what you'd change.** A retro naming three decisions you'd reverse, with reasons, demonstrates more engineering judgement than a project where everything went to plan — because projects where everything goes to plan are projects where nobody looked closely.

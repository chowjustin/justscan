# 02 · Contact Link  [MVP]

> Build order #2 · Est. 0.5 session
> Depends on: 01 · Consumed by: 03 catalogue (supplier), 04 sale (customer)
> Code location: `Core/Contacts/`

---

## 1. Purpose & scope

Turns "who is this supplier / customer" into two taps on the phone's own Contacts instead of a form. Owns the `CNContactPickerViewController` wrapper, the permission handling, and the **snapshot rule** that keeps supplier and customer names readable in old records after a contact is deleted, merged, or made unreadable by a revoked permission.

Built headless and early because both 03 and 04 depend on it, and because its failure modes (permission, stale identifier) are the kind that are cheap to design for and expensive to retrofit.

**Non-goals**

- Does not persist anything. It returns a value; the calling module stores it.
- Does not create, edit, or delete contacts. Read and pick only.
- Does not sync, cache, or mirror the address book.
- Does not read phone numbers, emails, or addresses. **Name and identifier only.**
- No custom contact-picker UI. The system picker is the product.

## 2. Roles & permissions

Single operator. iOS contact permission is a device-level gate, not an app role.

## 3. Flows

**Attach a contact (Operator)**
1. Operator taps "Pilih dari Kontak".
2. `CNContactPickerViewController` presents. **No authorization prompt appears** — the picker runs out-of-process, so the operator picking a contact is itself the consent.
3. Operator picks a contact → `ContactRef(id:, name:)` returned, name resolved by R-02-3.
4. Operator cancels → `nil`. Not an error.
5. Caller stores **both** fields on its own entity.

**Re-open a contact from a stored reference (Operator)**
1. A product detail or tender screen renders a stored supplier / customer name.
2. `ContactService.resolve(id:)` attempts a lookup — but **only when access has already been granted**. This path does require authorization, and a read-only screen must never be the thing that raises the prompt: the picker raises none, so this would be the app's only Contacts prompt, appearing at its least explicable moment.
3. Found → the name renders normally. **The contact card is not opened.** Presenting one requires `CNContactViewController.descriptorForRequiredKeys()`, which fetches phone numbers, emails, and postal addresses — flatly against R-02-6 and against this module's "name and identifier only" non-goal. Changing a supplier is detach-then-pick: two taps, no new surface, no extra keys.
4. Not found, or the fetch refused → show the stored `contactName` in secondary colour with a quiet note ("Kontak tidak ditemukan"). Never an error dialog, never a blank.
5. Access never granted → the name renders normally, unmarked. Nothing is known about whether the contact still exists, and marking it "gone" would be a guess dressed as a fact.

## 4. Rules & validations

| ID | Rule |
|---|---|
| R-02-1 | A contact reference is **always** stored as two fields: `contactID: String?` (the `CNContact.identifier`) and `contactName: String?` (a snapshot of the display name at pick time). Storing the identifier alone is forbidden. |
| R-02-2 | The name snapshot is **never** refreshed automatically. A product bought from "Budi" in January still reads "Budi" after the contact is renamed. Records describe what was true when they were written. |
| R-02-3 | Display name = `CNContactFormatter.string(from:style: .fullName)`. If that is nil or empty, fall back to `organizationName`. If that is also empty, fall back to `"Tanpa Nama"`. The snapshot is never nil or empty when `contactID` is set. |
| R-02-4 | `CNContact.identifier` is **not** guaranteed stable — it changes on merge and disappears on delete. Code must treat a failed resolve as normal, never exceptional. |
| R-02-5 | Both fields are set together or both are nil. A row with an ID but no name, or a name but no ID, is invalid state. |
| R-02-6 | Only `CNContactIdentifierKey` and the keys required by `CNContactFormatter` are requested. Requesting more is a privacy defect. |
| R-02-7 | Contact attachment is **always optional**. No flow in this app may block on a contact being chosen. |

## 5. Data model

**This module owns no entity.** It produces a value type that host entities embed as two columns.

```swift
struct ContactRef: Equatable, Sendable {
    let id: String       // CNContact.identifier
    let name: String     // snapshot, never empty (R-02-3)
}
```

A second value type crosses the boundary, so the framework does not have to:

```swift
enum ContactAccess: Equatable, Sendable {
    case notDetermined   // never asked. The picker still works — it prompts for nothing.
    case granted         // a lookup will be attempted. Covers iOS 18 limited access.
    case denied          // denied or restricted. The snapshot renders; nothing breaks.
}
```

Host mapping — identical field pair on both hosts:

| Host | Fields |
|---|---|
| `Product` | `supplierContactID: String?`, `supplierName: String?` |
| `Sale` | `customerContactID: String?`, `customerName: String?` |

Both nullable with default `nil`, per foundations §6.

## 6. States & transitions

None. `ContactRef` is an immutable value.

## 7. Module contract

**Exports**

```swift
protocol ContactServicing {
    @MainActor func pick() async -> ContactRef?              // nil == cancelled
    func resolve(id: String) async throws -> ContactRef?     // nil == gone
    var authorizationStatus: ContactAccess { get }
}
```

`authorizationStatus` returned `CNAuthorizationStatus` until session 2. That type cannot cross this boundary: naming it forces `import Contacts` on every caller **and on every conformance**, the test fake included, which makes AC-02-7 unsatisfiable by construction. The status crosses as `ContactAccess` instead, which is the whole point of the module — this folder is the only place that knows Contacts exists.

**Imports:** `POSError` from 01.
**Internal only:** the `CNContactPickerViewController` wrapper. No feature module imports `Contacts` directly — grep for `import Contacts` outside this folder is a review failure.

## 8. Edge cases

- **Operator cancels the picker.** `nil`. Caller leaves its fields untouched.
- **Contact deleted after being attached.** `resolve` returns `nil`. The stored `contactName` still renders. The product's supplier history is intact.
- **Contact renamed after being attached.** The snapshot does not change (R-02-2). Deliberate.
- **Contact merged.** The identifier may now point elsewhere or nowhere. Same handling as deleted.
- **Permission revoked in Settings while the app is backgrounded.** `pick()` still works — it is out-of-process. `resolve()` throws `contactAccessDenied`, caught, and the snapshot renders. **The app never loses data over a permission change.**
- **Contact with no name at all** (organisation-only, or empty). R-02-3 fallback chain guarantees a non-empty snapshot.
- **Same contact attached to 40 products.** Nothing special happens. There is no deduplication and none is needed; these are two denormalised columns, not a foreign key.

## 9. Service surface

| Type | Method | Purpose | Errors |
|---|---|---|---|
| `ContactServicing` | `pick()` | Present system picker | none — cancel returns nil |
| `ContactServicing` | `resolve(id:)` | Look up a stored identifier | `contactAccessDenied` |
| `ContactServicing` | `authorizationStatus` | Decide whether a live lookup is possible **without prompting** | — |

## 10. UI notes

This module ships no screens. It defines one reusable SwiftUI component that 03 and 04 both embed:

**`ContactField`** — a single row.

| State | Renders |
|---|---|
| Empty | `Pilih dari Kontak` with a `person.crop.circle.badge.plus` icon |
| Filled | The name, plus an `xmark.circle.fill` to detach |
| Filled, contact gone | The name in secondary colour with the note "Kontak tidak ditemukan", not tappable, no error. The detach control stays — a product whose supplier was deleted must still be re-pickable. |

Label text is supplied by the caller — "Supplier" in 03, "Pelanggan" in 04. The component is otherwise identical in both, which is the point of building it here.

## 11. Worked examples

```
Pick "Budi Santoso" (CN identifier ABC-123)
  → ContactRef(id: "ABC-123", name: "Budi Santoso")
  → Product.supplierContactID = "ABC-123"
    Product.supplierName      = "Budi Santoso"

Operator renames the contact to "Budi Grosir" in the Contacts app.
  → Product still displays "Budi Santoso"          (R-02-2)
  → resolve("ABC-123") returns "Budi Grosir"        (live lookup)
  → The product's stored snapshot is NOT updated.

Operator deletes the contact.
  → resolve("ABC-123") returns nil
  → Product still displays "Budi Santoso", untappable, secondary colour
  → No error is shown. The row is not broken.

Pick a contact with organisation "Toko Grosir Budi" and no person name.
  → ContactRef(id: "XYZ-789", name: "Toko Grosir Budi")   (R-02-3 fallback)
```

## 12. Acceptance criteria

| ID | Criterion |
|---|---|
| AC-02-1 | Picking a contact returns a `ContactRef` whose `name` is non-empty. |
| AC-02-2 | Cancelling the picker returns `nil` and throws nothing. |
| AC-02-3 | A `Product` with a `contactID` whose contact no longer exists renders its stored `supplierName` and shows no error. |
| AC-02-4 | Renaming a contact in the Contacts app does not change any stored `supplierName`. |
| AC-02-5 | With contacts permission denied, `resolve` throws `contactAccessDenied` and the calling screen still renders the snapshot. |
| AC-02-6 | A contact with only an organisation name yields that organisation name as the snapshot. |
| AC-02-7 | `import Contacts` appears nowhere outside `Core/Contacts/`. |
| AC-02-8 | Saving a product without choosing a supplier succeeds, leaving both fields nil. |

## 13. Build checklist

1. `ContactRef` value type
2. `ContactServicing` protocol + `FakeContactService` for tests and previews
3. `CNContactPickerViewController` presenter (not a representable — see `ContactPickerPresenter.swift`)
4. `resolve(id:)` with the R-02-3 name fallback chain
5. `ContactFieldViewModel` — the three states of §10 are decided here, because a View may not call a Service
6. `ContactField` SwiftUI component, all three states
7. Paired `supplier` / `customer` accessors on `Product` and `Sale`, so R-02-5 is structural
8. Tests for R-02-3 fallback and R-02-5 paired-nullability, against the fake

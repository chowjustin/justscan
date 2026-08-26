# CloudKit Hosting Checklist

> Referenced from `00_foundations.md` §6 and `DECISIONS.md` D-03.
> Run the **schema section** before writing any model. Run the **enablement section** when you actually turn sync on.

---

## Why this file exists

Two things are true at once, and they pull in opposite directions:

1. An incompatible model **still compiles**. Nothing in Xcode warns you.
2. The failure arrives at store load, as a very specific runtime error.

< cite index="9-1">An incompatible model still compiles. The useful failure arrives when SwiftData loads the CloudKit-backed persistent store, often as NSCocoaErrorDomain error 134060. If the CloudKit configuration only appears near release, that feedback arrives far too late.</cite>

That is the whole argument for enabling CloudKit **early** rather than at the end.

---

## Part 1 — Schema rules (check before writing any `@Model`)

< cite index="10-1">These rules are compulsory. Violating any of them results in sync failures or application crashes.</cite>

| # | Rule | Applies to |
|---|---|---|
| 1 | **No `@Attribute(.unique)` anywhere.** < cite index="10-1">CloudKit does not support atomic uniqueness checks across devices.</cite> | `Product.barcode` — moved to the repository (ADR-02) |
| 2 | **Every attribute is optional, or has a default value.** < cite index="10-1">A non-optional attribute with no default value is forbidden.</cite> | every field on all four models |
| 3 | **Every relationship is optional.** | `Product.movements`, `Sale.lines` |
| 4 | **Every relationship declares an explicit `inverse:`.** SwiftData can infer some, but not reliably. | both relationships |
| 5 | **No `.deny` delete rule.** Use `.cascade` or `.nullify` and enforce restrictions in code. | both relationships |
| 6 | **No ordered relationships.** Sort in code with an explicit `SortDescriptor`. | movement history, sale lines |
| 7 | **Enums stored as raw `String`, mapped explicitly, with a fallback for unknown values.** | `reasonRaw`, `statusRaw`, `paymentMethodRaw` |
| 8 | **Soft delete only.** Never `modelContext.delete()`. | `deletedAt` on `Product` |

### What the error actually looks like

Get one of these wrong and the store load throws with the offending fields named:

```
Error Domain=NSCocoaErrorDomain Code=134060
CloudKit integration requires that all attributes be optional, or have a default
value set. The following attributes are marked non-optional but do not have a
default value: Brew: brewDate  Brew: rating
CloudKit integration requires that all relationships be optional, the following
are not: Brewer: brews
CloudKit integration does not support unique constraints. The following entities
are constrained: Brew: brewIdentifier
```

**This is good news.** It is loud, specific, and names the exact fields. The danger was never the error — it's not seeing the error until the end of the project.

### The inverse trap

A missing `inverse:` is the sharpest edge here. One developer reported a model with < cite index="7-1">no `@Attribute(.unique)`, all properties defaulted, and relationships optional — which still crashed, because the inverse relationship needed to be explicitly defined. The same model loaded fine on iOS 17.3 and crashed on 17.4.</cite>

So: **always write `inverse:` explicitly**, even when SwiftData appears to infer it correctly. Inference that works today is not a guarantee.

---

## Part 2 — Enablement steps

Only when you're actually turning sync on.

- [ ] **Paid Apple Developer Program membership.** iCloud entitlements are not available under free personal-team provisioning. This is a hard gate, not a soft one.
- [ ] Signing & Capabilities → **+ Capability → iCloud** → check **CloudKit**.
- [ ] Create or select a container: `iCloud.chow.JustScan` — exact casing, matching the bundle ID `chow.JustScan`.
- [ ] Add the **Background Modes** capability → **Remote notifications**. Without it, changes from other devices only arrive on next launch.
- [ ] Change the container config:
      ```swift
      ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
      ```
- [ ] Launch on a real device signed into iCloud. **Read the console.** A 134060 here means go back to Part 1.
- [ ] Push the schema to the CloudKit dashboard. < cite index="12-1">SwiftData does not expose a top-level API for this, so drop to the Core Data layer and call `initializeCloudKitSchema()` — and do not keep it in production code, since it is an expensive network operation. Run it during development or after model changes, verify in the dashboard, then guard it behind `#if DEBUG`.</cite>
- [ ] Verify records appear in the CloudKit Dashboard under **Development**.
- [ ] Test on a second device signed into the same account.
- [ ] Only when confident: promote **Development → Production** in the dashboard.

---

## Part 3 — What CloudKit costs you (accept these before enabling)

### The toggle-later trap ⚠️

**This is the one that changes the plan.** Switching an existing local store to CloudKit is not a clean checkbox. A developer shipping sync as a paid upgrade reported: < cite index="13-1">free users get a container with `cloudKitDatabase: .none`, and when a user upgrades and the container restarts with `.automatic`, the app crashes immediately on launch with `loadIssueModelContainer` — SwiftData fails to load the existing data once the configuration expects a CloudKit-backed store.</cite>

**Consequence for this project:** "local now, iCloud later" is safe for *your own dev data*, which you can wipe. It is **not** safe for a shop that has been using the app for six months. If sync is ever turned on for a live install, plan a migration — export, reinstall with CloudKit on, reimport — not a config flip.

### Uniqueness has no replacement

< cite index="9-1">Removing `.unique` leaves a real hole. SwiftData maintains the identity of each persistent object, but it does not stop two offline devices from creating two records for the same logical event, and mirroring will not invent that business rule. A deterministic fingerprint can help the app detect equivalent records after fetching them, but automatic mirroring cannot enforce it as a global unique constraint.</cite>

Repository-enforced uniqueness (ADR-02) is **per-device**. Two devices offline can both create "Chitato" with barcode `8992775311011`. Deduplication after the fact would be a new feature — note it in the deferral register if sync ever becomes real.

### The production schema is append-only

< cite index="9-1">A production CloudKit schema is additive. Once deployed, existing record types and fields cannot simply be removed or have their types changed. Treat those edits as migration decisions.</cite>

Promoting to Production is close to irreversible. Stay in Development until the model has genuinely settled.

### Full iCloud storage takes the whole store down

One reported failure mode: < cite index="14-1">when CloudKit storage is full, `ModelContainer` initialization fails completely and local data also stops being saved</cite> — rather than degrading gracefully to local-only. For a POS this is severe: a full iCloud account would stop the shop trading. If sync becomes real, wrap container creation in a fallback to a local-only configuration.

---

## Part 4 — Where the project stands

The schema in `00_foundations.md` §6 already satisfies **every rule in Part 1**.

Per **D-18**, Part 2 runs in session 1 — CloudKit is enabled from the start, so every launch validates the schema. Part 3's failure modes are handled by **R-01-9**: container creation tries CloudKit, falls back to local-only, and never blocks trading.

**Do not promote Development → Production** until the model has settled. That step is in the deferral register.

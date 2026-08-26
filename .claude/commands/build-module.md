---
description: Build one module strictly from its spec, with a plan-review gate
argument-hint: '[module number, e.g. 03]'
---

You are implementing module $ARGUMENTS of the JustScan iOS app.

## STEP 1 — Load, in this order

- @docs/specs/PROGRESS.md — where we are, what already exists
- @docs/specs/00_foundations.md — conventions, entity map, error registry, seed, golden path
- @docs/specs/$ARGUMENTS\*.md — **this module. It is the contract.**

`CLAUDE.md` is already loaded. If any module is already built, skim one for pattern parity before planning.

## STEP 2 — Plan. Do NOT create or edit a single file yet.

Produce a plan mapped 1:1 to the spec's sections, in this order:

1. **Models** (§5) — every field, with its type, optionality, and default
2. **Repository** — protocol first, then the concrete type
3. **Service** (§7 exports) — signatures copied verbatim from the spec
4. **Rules** (§4) — which rule is enforced in which function. Every `R-$ARGUMENTS-*` must appear.
5. **ViewModel**
6. **Views** (§10)
7. **Tests** — one per rule, one per acceptance criterion in §12

Then, before you stop, list:

- **Every point where the spec is ambiguous, silent, or contradicts another spec.**
- Every place you were tempted to add something the spec does not mention.

**STOP and ask about all of them. Do not guess. Do not fill gaps.** A `⚠️ OPEN` marker in a spec is a hard stop.

Wait for my approval before touching any file.

## STEP 3 — Implement (only after I approve)

Follow the approved plan. Non-negotiable, from `CLAUDE.md`:

- **Layering:** View → ViewModel → Service → Repository → ModelContext. Never skip an arrow, never reverse one.
- **No `@Query` in any view.** No `import SwiftData` in any view.
- **Money is `Int` rupiah.** No `Decimal`, `Double`, or `Float` in models or services.
- **No `@Attribute(.unique)`.** Uniqueness is enforced in the repository, inside the service call.
- Every stored property optional or defaulted. Every relationship optional with an explicit `inverse:`.
- Soft delete via `deletedAt`. Never `modelContext.delete()`.
- **One `save()` per business operation.** Two saves in one service method is a failure.
- Cross-module calls go through the §7 exported interfaces only. No reaching into another module's repository.
- Code and identifiers in English. Every operator-facing string in Indonesian.

Build in the plan's order: models and repository first, service and its tests next, views last. **Do not write a view before its service tests pass.**

## STEP 4 — Definition of done

Run these now and fix what fails:

- [ ] Every acceptance criterion in §12 passes
- [ ] Every rule in §4 is enforced somewhere, with a test for every computed one
- [ ] The worked examples in §11 produce **exactly** the stated numbers — not approximately
- [ ] Exported signatures match §7 character for character
- [ ] Every error thrown is in the foundations §7 registry, and each has an Indonesian message
- [ ] `grep -rn "Double\|Float\|Decimal" Core/ Models/ --include=*Service.swift` → no hits
- [ ] `grep -rn "@Attribute(.unique)\|@Query" .` → no hits
- [ ] Build passes, all tests pass

Report §12 as a **pass/fail table**, one row per criterion, each naming the test or code that satisfies it. `13/16` is a fact; "mostly done" is a feeling and is not accepted.

## STEP 5 — Record

Update `docs/specs/PROGRESS.md`:

- Module status and `N/M` criteria passing
- Every deviation from spec, with its reason and whether the spec was updated
- Any new open question

If you had to deviate: **update the spec first, then the code**, and add a row to `DECISIONS.md` under Reversed. A spec that lags the code is worse than no spec, because the next session trusts it.

Finally, propose a conventional commit message. Do not commit without showing it to me.

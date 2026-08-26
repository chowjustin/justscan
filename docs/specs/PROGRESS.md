# Build Progress

Read this file **first** at the start of every session. Update it at the end of every session, before committing.

## Current

- **Active module:** none — no code exists yet
- **Session goal:** 01 App Shell
- **Next up:** 02 Contact Link

## Status

| Module | Status | Acceptance criteria passing | Notes |
|---|---|---|---|
| 01 App shell | todo | 0/8 | Start here. Sets every pattern the other four copy. |
| 02 Contact link | todo | 0/8 | Headless, no screens of its own |
| 03 Catalogue | todo | 0/16 | Largest data model |
| 04 Sale | todo | 0/18 | Largest module. Build nothing else that session. |
| 05 History | todo | 0/9 | Read-only |

**Total: 0/59 acceptance criteria.**

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
| — | none yet | | |

Record every deviation here the moment it happens. An undocumented deviation is how a codebase stops matching its spec.

## Open questions raised during build

- [ ] none yet

## Conventions added this build

Mirror anything added here into `CONVENTIONS.md`.

- none yet

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
| — | — | not yet run | — |

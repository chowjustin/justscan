---
description: Run the end-to-end golden path as the final gate. Audit only.
---

Run the golden path in `@docs/specs/00_foundations.md` §10 — ten numbered steps, end to end.

## How

Prefer an **automated integration test** that drives the services directly, over manual clicking. It is repeatable, it can live in CI, and it is the artifact that proves the system works. Write it as a single test that walks all ten steps in order against a fresh in-memory container.

Where a step is genuinely UI-only (the 300 ms scan-to-line target, the sub-1-second cart reset), say so and verify it by hand on device.

## Report

| Step | Expected | Actual | Pass/Fail |

The numbers in §10 are exact. `Rp 29.000` means `29000`, not `29001`. `changeRp` for QRIS means `nil`, not `0`.

Pay closest attention to the three steps that catch the subtle bugs:

- **Step 5** — scanning the same product twice must produce **one line at qty 2**, not two lines.
- **Step 8** — the void must restore both products to their exact pre-sale quantities, **and** retain the sale number `20260821-001`.
- **Step 10** — `recompute()` must return the same number the cache already held. If it does not, the cache and the ledger have diverged, and that is the most serious class of bug in this system.

## Then

Record the run in `docs/specs/PROGRESS.md` under Golden path: date, result, and every failure.

**Fix nothing in this pass.** Failures become a `/build-module` run against the module that owns the broken behaviour.

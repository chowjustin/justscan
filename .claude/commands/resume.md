---
description: Resume an in-progress module with full continuity
argument-hint: "[module number, e.g. 04]"
---

Resume module $ARGUMENTS.

## Load

- @docs/specs/PROGRESS.md
- @docs/specs/$ARGUMENTS*.md
- Then **inspect the repo** for what already exists in this module. Trust the code over `PROGRESS.md` where they disagree, and flag the disagreement.

## Report before doing anything

1. **Done** — which acceptance criteria already pass, with the test or code that proves each.
2. **Left** — which do not, in the spec's build-checklist order (§13).
3. **Drift** — anything in the code that the spec does not describe, or vice versa.
4. **Open questions** logged against this module in `PROGRESS.md` or `DECISIONS.md`.

## Then continue

Start from the first unfinished item in §13.

- **Do not redo completed work.** If a service exists and its tests pass, leave it alone.
- Match the patterns already established in this module, even where you would have chosen differently. Consistency inside a module beats your preference.
- If existing code violates `CLAUDE.md` — a `@Query` in a view, a `Double` in a service, a second `save()` — **stop and report it** rather than silently building more on top of it.

Finish with the same STEP 4 and STEP 5 as `/build-module`: the pass/fail table, then update `PROGRESS.md`.

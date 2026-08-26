---
description: Audit a module against its spec. Audit only — change nothing.
argument-hint: "[module number, e.g. 03]"
---

Audit module $ARGUMENTS against @docs/specs/$ARGUMENTS*.md and @docs/specs/00_foundations.md.

**Run this in a fresh session, never right after `/build-module`.** An agent auditing code it just wrote, in the same context, grades generously — it remembers what it meant rather than reading what it wrote.

## Report, in this order

**1. Acceptance criteria** — one row per `AC-$ARGUMENTS-*`:

| ID | Pass/Fail | Evidence (file:line, or the test that proves it) |

A criterion that passes only under a generous reading is **failing**. If you need a sentence of justification, mark it FAIL.

**2. Rules** — one row per `R-$ARGUMENTS-*`, naming the exact function that enforces it, or `MISSING`.

**3. Contract** — does every signature in §7 match the code character for character? List any drift.

**4. Worked examples** — run each §11 example. Do the numbers come out exactly right?

**5. Convention violations** — check and report hits for each:

```
grep -rn "Double\|Float\|Decimal" Core/ Models/ Features/ --include=*.swift
grep -rn "@Attribute(.unique)" .
grep -rn "@Query\|import SwiftData" Features/**/*View.swift
grep -rn "modelContext.delete\|try?" Core/ Features/
grep -rn "import Contacts" --include=*.swift . | grep -v Core/Contacts
```

Also confirm: every model property optional or defaulted · every relationship optional with an explicit `inverse:` · no service method calls `save()` more than once.

**6. Registry drift** — do the entities in this module match the foundations §4 entity map exactly? Does every error thrown appear in the §7 error registry?

**7. Summary** — `N/M` criteria passing, and the single most serious gap found.

## Rules for this pass

**Fix nothing. Change no file.** If you find a bug, describe it and stop. The fix is a separate `/build-module` run, so that the audit and the repair never share a context.

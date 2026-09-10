---
name: linting
description: 'Unified lint workflow for changed shell and markdown files. Use when touched scope includes .sh or .md and return one consolidated report.'
argument-hint: 'Provide changed-file scope, branch/diff context, and whether warnings are blocking.'
---

# Unified Linting

## When to Use
- Any task that touches `.sh` or `.md` files.
- Implementation, review, security review, docs updates, and context maintenance.

## Procedure
1. Determine touched scope.
   - Prefer changed files; widen only when requested.
2. Build lint targets.
   - Shell targets: changed `*.sh` files.
   - Markdown targets: changed `*.md` files.
3. Verify tool availability.
   - `shellcheck` for shell files.
   - `markdownlint-cli2` for markdown files.
4. Run linters.
   - Shell: `shellcheck -x <files>`.
   - Markdown: `markdownlint-cli2 <files>`.
5. Triage findings and apply in-scope fixes.
6. Re-run linters on touched files.

## Decision Points
- No `.sh` and no `.md` touched: return no-op.
- Missing linter dependency: report exact missing tool and stop.
- Out-of-scope findings: report separately; do not broaden edits.

## Consolidated Report Format
- Scope: files checked by type.
- Commands: exact commands executed.
- Results: pass/fail per linter.
- Remaining findings: unresolved items with deferral reason if any.

## Completion Criteria
- All relevant touched `.sh` and `.md` files were linted.
- Required fixes applied or explicitly deferred.
- One consolidated report is included in final output.

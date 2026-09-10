# Bash Coding Standards

## Purpose

This file defines compact, maintainable Bash standards for this repository.
Use it when creating, updating, or refactoring shell scripts, especially installers in scripts/.

## Scope

- Applies to `bootstrap.sh` and `scripts/*.sh`.
- Applies to noun-based component commands in `scripts/` and their shared helpers.

## Lifecycle Interface

- Name entry points after their component (`alacritty.sh`, `herdr.sh`), not an
  action or release channel. Keep shell/Python extensions; remove redundant
  action prefixes and suffixes. Utilities and libraries use noun categories too.
- Every component exposes `install`, `update`, `uninstall`, `check` and common
  `--dry-run` handling. Require an explicit action; reject invalid input before
  side effects. Retain useful domain nodes, such as Ghidra `run` or desktop `export`.
- Route lifecycle parsing, receipts and common checks through `delib.sh` and
  `lifecycle.py`; keep component installation policy in its noun file. Helpers
  need meaningful domain commands, not artificial lifecycle no-ops.
- Update converges to configured pins; only explicitly versionless packages
  track new releases. Build Alacritty from its exact development revision and
  verify the produced version before installing, never copy an existing binary.
- Check is read-only. Dry-run never downloads, installs, writes reports, acquires
  sudo or changes services. Removal verifies receipts and hashes, refuses apt
  dependency cascades and preserves configuration and persistent data.
- Bootstrap forwards the selected action in dependency order, verifies all
  selected removals first and uninstalls in reverse order. Require explicit
  component selection for uninstall. Update callers/docs when moving scripts;
  do not leave old command aliases or duplicate implementations behind.

## Context Documentation Compaction Policy

- Applies to markdown documents under `.github/context/`.
- If any context markdown document exceeds 25K tokens, compact it in place.
- During compaction, preserve critical facts, source traceability, and canonical policy references.
- Keep updates concise and non-duplicative, and synchronize `INDEX.md` and `GLOSSARY.md` when context terms or subjects change.

## Core Style

- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Keep scripts tight and compact, but not cryptic.
- Prefer short single-purpose functions.
- Keep naming explicit and consistent.
- Fail fast with clear, prefixed errors.

## Shared Library Practice

1. Put common installer logic and encountered, reusable helper functionality in `scripts/delib.sh`.
2. In installer scripts, always source the shared library via:
   - `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
   - `export INSTALL_LIB_TAG="<script-tag>"`
   - `source "${SCRIPT_DIR}/delib.sh"`
3. Do not duplicate helpers that already exist in `scripts/delib.sh`.
4. Shared concerns that belong in `scripts/delib.sh`:
   - prefixed logging
   - sudo authentication flow
   - apt idempotent update/install logic
   - required-command checks
   - option-value validation
   - distro codename resolution helpers
   - environment variable management
   - toolchain environment management

## Argument Parsing Standard

1. Implement `usage()` and `parse_args()` in every non-trivial script.
2. Parse with `while [[ "$#" -gt 0 ]]; do case "$1" in ... esac; done`.
3. Support `-h|--help` consistently.
4. Use `require_option_value` for options that require a value.
5. Reject unknown flags with a non-zero exit and usage output.
6. Parse arguments before side effects.

## Simplification Rules

- Prefer `apt_install_missing` over repeated apt package checks.
- Avoid branching duplication; centralize shared behavior.
- Avoid unnecessary subshells and command pipelines when a direct command is clear.
- Keep environment override behavior explicit and documented.

## ShellCheck Standards

1. Scripts must pass `shellcheck -x` where feasible.
2. Quote variable expansions unless intentional word splitting is required.
3. Prefer arrays for command argument forwarding.
4. Use `[[ ... ]]` for tests.
5. Add shellcheck source hints for sourced files, for example:
   - `# shellcheck source=./delib.sh`

## Edge Case Coverage Requirements

- Handle root and non-root execution correctly.
- Validate required commands before use.
- Use noninteractive apt invocation for installer automation.
- Handle missing distro codename data with fallback logic and explicit failure.
- Validate service operations when `systemctl` is unavailable.
- Clean up temporary files in both success and failure paths where applicable.
- Ensure scripts that are libraries are not executable entry points.

## Refactor Checklist

1. Refactor duplicated helper logic into `scripts/delib.sh`.
2. Keep behavior unchanged unless explicitly requested.
3. Re-run syntax checks (`bash -n`) on touched scripts.
4. Re-run diagnostics and fix ShellCheck-style issues that affect changed code.
5. Verify bootstrap dry-run still works after refactors.

## Manager Orchestration Policy

1. For code-producing tasks, review order is mandatory:
   - Code Reviewer first (standards compliance)
   - Security Analyzer second (security review)
2. Default review scope is changed files only unless explicitly widened.
3. Implementation agent should not close a task before required blocking findings are addressed or explicitly deferred by user.
4. Per-task override is allowed only for approved medium-severity deferrals in scoped workflows (for example docs-only or low-risk hotfix).

### Per-Task Override Rules

- Only Project Manager can grant an override.
- Overrides may defer medium findings only.
- High findings are never overridable.
- Each override must record: rationale, scope, deferred findings, and follow-up action.
- Executor must not self-grant overrides; it may only apply explicit Project Manager override instructions.

## Review Severity Gates

## Code Reviewer Responsibilities

- Treat this file as the canonical policy for standards review behavior and severity handling.
- Identify duplicated functionality in reviewed changes and report lift candidates to shared/common code.
- For shell scripts, recommend consolidating reusable logic into `scripts/delib.sh` when appropriate.
- Include concrete evidence for duplication findings (source file/functionality and proposed shared target).

### Code Reviewer Gates

- High: blocking; fix before completion.
- Medium: expected to fix in current pass unless Project Manager explicitly overrides for this task.
- Low: non-blocking; report as follow-up recommendations.

## Security Analyzer Responsibilities

- Treat this file as the canonical policy for security-review severity handling.
- Follow security policies documented in `.github/context`, including project-specific policies in `.github/context/PROJECT/`.
- Apply repository security guardrails from project context when reviewing installer/bootstrap and overlay-related changes.
- Report policy violations with concrete file/line evidence and required remediations.

### Security Analyzer Gates

- High: blocking; must fix before completion.
- Medium: blocking by default; only Project Manager may explicitly override for this task.
- Low: non-blocking; report with mitigation guidance.

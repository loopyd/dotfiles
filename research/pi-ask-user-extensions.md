# Research: pi "ask user" / "interview" extensions

Date: 2026-09-30. Scope: extensions that let the LLM ask the user interactive questions mid-run.

## TL;DR

**@juicesharp/rpiv-ask-user-question is the clear winner** — 274.8K/mo downloads (107.6K/wk), MIT, no native deps, no API keys, no model calls of its own. One tool (`ask_user_question`), up to 4 questions in one tabbed terminal dialog with typed options, free-text, per-question + global notes, markdown previews, Submit review tab, BEL bell, and it works in TUI, RPC, and ACP hosts (VS Code, Zed).

Runner-up: **pi-interview** (18.9K/mo) — richer media (images, charts, Mermaid) but renders in a browser/Glimpse window, not the terminal.

## Ranking (by popularity)

| # | Package | Downloads/mo | GitHub stars | Tool | UI surface | Notes |
|---|---------|-------------|--------------|------|------------|-------|
| 1 | `@juicesharp/rpiv-ask-user-question` (v2.12.0) | 274.8K (107.6K/wk) | 856 (rpiv-mono) | `ask_user_question` | Terminal dialog (TUI), native dialogs in RPC/ACP | Most popular by a wide margin. Up to 4 questions, 2–4 options each, "Type something." row, notes, markdown previews, Submit tab, `Ctrl+]` collapse, BEL. Node 22+, 100+ col terminal for side-by-side previews. No native deps, no API keys, no model calls. |
| 2 | `pi-interview` (v0.13.0, nicopreme) | 18.9K (4,207/wk) | 316 (nicobailon/pi-interview-tool) | `interview()` | Browser tab / native macOS Glimpse window / Orca tab | Rich media: single/multi-select, text, image upload + camera, charts (Chart.js), Mermaid, tables, HTML, code/diff content blocks, recommended options with conviction/weight, "Other", attachments, keyboard nav, auto-save (localStorage), session timeout with countdown, multi-agent queueing, session recovery + snapshots, `async: true` mode, remote/SSH/Moshi support. Requires pi ≥0.82.1. |
| 3 | `pi-ask-user` (edlsh) | n/a (low) | 165 | `ask_user` | Terminal overlay (modal) or inline | Searchable options, split-pane details preview, multi-select, freeform, user-toggleable comments, `alt+o` overlay toggle, timeout, `herdr:blocked` lifecycle events, bundled `ask-user` skill enforcing decision-gating. Env-var config (`PI_ASK_USER_*`). |
| 4 | `@nguyenquangthai/pi-ask` (v0.2.1) | 422 | 4 | `ask_user_question` | TUI-only keyboard-first dialog | 1–4 questions, review tab, conditional follow-ups (`showWhen`), recommended options, skip rows for optional, multi-select, IME-safe, auto "Other" row. Heavy test suite (reducer, keyboard, real-TUI e2e, real-CLI e2e). Disabled outside TUI mode. Inspired by Claude Code's AskUserQuestion. |
| 5 | Others (new/niche, ~0 stars/downloads) | — | 0–1 | various | various | `Givdul/pi-ask-user-question` (T3 Code cards + fallback), `egornomic/pi-branch-ask` (branching questions), `forjd/forjd-pi` (bundled set), `tectiv3/pi-extensions`, `@qmahyar/pi-ask`, `@josephyoung/pi-ask-user-question`, `ghoseb/pi-askuserquestion`, `leninkhaidem/pi-ask-user-question`, `@fyeeme/pi-ask-user-lite` (sister of pi-ask-user), `@arvoretech/pi-ask-user-question`, `jqwn/pi-ask-user-question`, `jyooi/pi-ask-user-question` |

## Built-in context (pi itself)

Pi has **no built-in "ask user" tool**. Relevant primitives:

- `ctx.ui.confirm(prompt)` — yes/no confirmations (used by permission extensions).
- `ctx.ui.custom()` — custom TUI components with their own rendering/input (the mechanism all the extensions above use).
- SDK `session.prompt()` / `steer()` / `followUp()` — programmatic user input, not model-initiated.
- Extension docs mention "model-only" tools: declared to the model while active, never callable — use for tools that orchestrate other tools **or ask the user**.

So an extension registering a tool is the correct and idiomatic approach.

## Recommendation

- **Default choice: `@juicesharp/rpiv-ask-user-question`** — most used, most maintained (published Sep 30, 2026), terminal-native, no external dependencies, works across TUI/RPC/ACP hosts. Install: `pi install npm:@juicesharp/rpiv-ask-user-question`.
- **If you need rich media (images, charts, diagrams) or a non-terminal UI: `pi-interview`** — but it opens a browser/Glimpse window, which is heavier and less suited to headless/remote workflows.
- **If you want strict decision-gating behavior (agent must ask before high-impact assumptions): `pi-ask-user`** — bundles a skill that mandates the `ask_user` flow for architectural trade-offs and ambiguous requirements.

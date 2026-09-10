# Copilot Repository Context

Use the following files as canonical global context before planning or implementation:

- `.github/context/PROJECT/system-context.md`
- `.github/context/PROJECT/coding-standards.md`
- `.github/skills/linting/SKILL.md`

Before creating or refactoring any code, follow `.github/context/PROJECT/coding-standards.md` for shared-library use, argument parsing, and severity gates.

## Roles and Delegations

- Primary orchestrator: Project Manager.
- Planning: Planner.
- Implementation: Executor.
- Standards review: Code Reviewer.
- Security review: Security Analyzer.
- Documentation: Writer.
- Repository knowledgebase and historical context CRUD management: Researcher.

### Delegation Defaults

- For code-producing tasks, review order is mandatory:
	1. Code Reviewer
	2. Security Analyzer
- Documentation tasks should be delegated to Writer.
- `.github/context` curation and lookup should be delegated to Researcher.

### Research Policy

- Researcher may use Context7 (`io.github.upstash/context7/*`) and web search for API/product documentation.
- Prefer Context7 and official vendor docs as primary sources before checking the web.
- External findings should be persisted as concise markdown in `.github/context/<subject>/`.
- Researcher must keep `.github/context/INDEX.md` and `.github/context/GLOSSARY.md` synchronized with new findings.

### Linting Policy

- Use unified `linting` skill for touched `.sh` and `.md` scope.
- Require one consolidated lint report containing:
	- checked file scope
	- commands executed
	- pass/fail status
	- unresolved findings and deferrals
- Prefer changed-file scope by default; widen only when explicitly requested.

## Working Rules For This Repository

- Treat `/etc` and `/usr` findings as read-only inventory context unless explicitly instructed otherwise.
- Prefer user-scoped sync candidates from `~/.config` and `~/.local` using allowlist strategy.
- Preserve and respect credential protections enforced by `.githooks/pre-commit`.
- Prefer incremental updates to the canonical context file by refining sections in place.

## Overlay and Security Guardrails

- Do not store host-derived symlinks in repository overlay; recreate required symlinks via bootstrap/scripts.
- Do not commit user bin artifacts (for example `.local/bin`) or bin-target symlinks; recreate required wrappers/links in bootstrap/scripts.
- Keep sensitive paths excluded from capture and summaries (ssh, gpg, browser/session/account stores).
- Avoid broad refactors outside requested scope; report out-of-scope findings separately.

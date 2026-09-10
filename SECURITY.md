# Security Policy

## Credential Guard

The pre-commit hook runs `scripts/guard.py --staged` against complete staged
blobs, including overlay-prefixed paths. It blocks known credential formats,
literal credential assignments, account/session/database paths, private keys,
host symlinks and user-bin overlays. Diagnostics show paths and categories only.
The capture tool replaces sensitive values with rendering markers; private
values stay outside Git. Before publishing a capture, also run the guard with
`--values /private/path/values.json` to detect exact known-value leaks.

Hook path:

- `.githooks/pre-commit`

What it blocks:

- High-risk paths, including:
  - `.config/gh/`
  - `.config/google-chrome/`
  - `.config/mozilla/`
  - `.config/discord/`
  - `.config/Code/User/globalStorage/`
  - `.local/state/`
- Common sensitive filenames and extensions (`.env`, `.netrc`, `.npmrc`, `.pypirc`, private key names, `*.pem`, `*.p12`, `*.pfx`, etc.)
- Credential literals in complete staged files (GitHub, GitLab, Slack, AWS access IDs, API keys, JWT, private keys, OpenAI and Hugging Face)
- Authorization and URL credential patterns (Bearer and Basic headers, plus `user:pass@host` URL style credentials)
- Literal personal-account and credential assignments, rather than unrelated mentions of credential terminology in documentation or scanner source

Rendering markers are recognized syntactically; no runtime secret is exempted.
Markdown may retain explicit `your-...` / `sk-your-...` example values and quoted
PEM headers without key payloads; runtime configuration
does not receive that exception. APT signing keyrings under `root/etc/apt/keyrings`
are allowed only when GnuPG parses them as public packets without secret packets.
Do not disable the hook to publish a capture. `root/home/user/.local/bin` remains
blocked: authored launchers live under `templates/commands/` and are created by
the renderer. Runtime SQLite exports and private values must not be staged;
9router configuration is represented by a sanitized JSON template instead.

## Installing Hooks Locally

Run once per clone:

```bash
./scripts/hooks.sh install
```

Or manually:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
```

If the hook blocks a commit, remove or redact the sensitive data, then re-stage and commit again.

If any real credential has been committed at any point, rotate or revoke it immediately.

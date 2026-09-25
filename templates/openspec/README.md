# OpenSpec project template

`config.yaml` is the canonical project configuration `scripts/openspec.py scaffold`
copies over the file `openspec init` generates. It seeds the project context and
leaves artifact rules and per-operation guidance commented for the project to opt
into.

Scaffold a project from anywhere with the installed wrapper:

```bash
openspec-init /path/to/repo      # default: current directory
```

That runs `openspec init --tools pi,codex`, then replaces `openspec/config.yaml`
with this template. The CLI and the global Pi/Codex integration are managed by
`./scripts/openspec.sh`; this template only shapes a single project's plan.

# Native CLI Agent Runbook

## Codex

Use Codex as the release reviewer by default.

Review a commit:

```bash
codex review --commit <sha> "$(cat .codex/agents/release-reviewer.md)"
```

Review current dirty tree:

```bash
codex review --uncommitted "$(cat .codex/agents/release-reviewer.md)"
```

Run RCA audit prompt:

```bash
codex exec "$(cat .codex/agents/rca-auditor.md)"
```

## Claude

Use Claude as the builder/workflow owner by default. Load project agents explicitly:

```bash
claude --agents "$(cat .claude/agents/agents.json)" --agent premium-license-workflow
```

Other Claude agents:

```bash
claude --agents "$(cat .claude/agents/agents.json)" --agent downloader-runtime-workflow
claude --agents "$(cat .claude/agents/agents.json)" --agent release-readiness-workflow
```

## Required Handoff From Claude To Codex

```md
Task packet:
Commit/diff:
Tests run:
Production data authority:
Assumptions:
Requested review mode: release blockers only | full code quality
```

## Required Codex Output

Codex must end with one verdict from `docs/ops/REVIEW_VERDICT_PROTOCOL.md`.

## Hard Gates

- Do not push, tag, release, register release, force-update, or mutate billing/license state without explicit approval.
- Do not use `.claude/settings.local.json` or session history as a shareable policy source.
- Do not install third-party plugins/skills to solve operating discipline.

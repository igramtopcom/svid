# Snakeloader AI Operating Contract

## Purpose

Snakeloader is past the fast-build/vibe phase. The goal of Claude/Codex is not maximum autonomy; it is maximum verified throughput without release churn, false RCA, or hidden production risk.

This contract applies to Claude Code, Codex CLI, subagents, and any workflow derived from their outputs.

## Phase -1 Findings To Preserve

- Release/push gates were repeatedly corrected by the user. Agents must not ship, push, tag, register releases, force-update, or mutate production without explicit approval.
- Evidence/RCA gates failed repeatedly. Multi-agent "RCA CONFIRMED" verdicts collapsed under hands-on verification.
- UI/design work looped because "better" was not tied to acceptance criteria or stop conditions.
- Agent collision occurred when Claude and Codex treated each other as authorities instead of bounded roles.
- User frustration often caused agents to rush or over-accommodate. Frustration is a brake signal.

## Authority Model

- Human owner: product direction, release approval, force-update, rollback, billing/license mutation, credentials, remote trust, and final GO/NO-GO.
- Claude: builder/workflow owner. It may research, implement, verify, commit, and produce proof packs inside the task packet.
- Codex: reviewer/release gate. It may block only with a P0/P1 that meets the blocker standard.
- Telemetry team/workflow: data authority only for the data it actually pulled. Telemetry is not mechanism proof.
- Existing docs/memory: leads and context, not current truth unless rechecked against repo, runtime, or production evidence.

## Required Task Packet

Before any non-trivial task, define:

- Mission
- Scope
- Out of scope
- Authority
- Success criteria
- Known risks
- Allowed autonomy
- Stop condition
- Required proof
- Release gate

Use `docs/ops/TASK_PACKET_TEMPLATE.md`.

## Work Modes

Research mode:

- Read-only by default.
- Output claims as `VERIFIED`, `HYPOTHESIS`, `UNKNOWN`, or `RETRACTED`.
- No code edits unless the task packet changes mode.

Implementation mode:

- Touch only files needed for the task.
- Preserve dirty user work.
- Add or update targeted tests for behavior changes.
- End with proof: commands, test results, and remaining risks.

Review mode:

- Findings first, ordered by severity.
- Block only with the blocker standard.
- Do not block on missing personal access to data if a named authority produced that data; mark assumption instead.

Release mode:

- Requires explicit human approval in the current thread.
- Must state remote, branch, version, artifacts, verification gates, and rollback path.
- No release if the working tree contains unexplained changes in release-critical files.

## Blocker Standard

A release blocker must include all of:

- Severity: P0 or P1.
- Evidence: file/line, test failure, runtime proof, or production proof.
- User impact: who is harmed and how.
- Release consequence: why shipping now is unsafe.
- Minimal fix path: the smallest change or gate that resolves the blocker.

If any item is missing, classify as `FOLLOW-UP` or `SIGN-OFF WITH ASSUMPTIONS`, not `BLOCK RELEASE`.

## RCA Discipline

- Telemetry answers where and how large.
- Code read proposes mechanism.
- Repro or instrumentation proves mechanism.
- Root cause is not confirmed until all three line up.
- Payment/license incidents need proof that money moved or entitlement moved.
- Pending transaction counts are not revenue impact without payment-capture proof.

Forbidden wording without proof:

- `RCA CONFIRMED`
- `root cause closed`
- `production safe`
- `release ready`
- `paid users stranded`

Use bounded wording:

- `symptom verified, mechanism unconfirmed`
- `code-confirmed recovery gap`
- `releaseable under assumptions`
- `telemetry lead, needs spot-check`

## Claude/Codex Handshake

Claude handoff to Codex must include:

- Task packet.
- Diff/commit scope.
- Tests run.
- Data sources and which session verified them.
- Known assumptions.
- Explicit request: `review for release blockers only` or `review for full code quality`.

Codex verdict must be one of:

- `SIGN-OFF`
- `SIGN-OFF WITH ASSUMPTIONS`
- `BLOCK RELEASE`
- `FOLLOW-UP`

Claude response to Codex must be one of:

- `ACCEPT`: fix minimally.
- `REJECT WITH EVIDENCE`: explain why the finding is invalid.
- `DEFER`: record as follow-up because it is non-blocking.
- `ASK HUMAN`: only for product/release/credential/remote decisions.

## Production And Secret Rules

- Never expose secrets, tokens, private URLs, env dumps, or credential-bearing commands.
- Do not commit `.claude/settings.local.json`, session history, auth files, or copied command logs with tokens.
- Do not broaden allowlists, install plugins, add MCP servers, or change global config without explicit approval.
- Prefer extracting small reviewed workflow text over installing third-party harnesses.

## UI/UX Work Rules

- Design direction is human-gated.
- AI may generate variants, rubrics, and implementation candidates; it cannot decide taste by authority.
- Every design loop needs a rubric, max iterations, and a stop condition.
- For Snakeloader home/app UI, read `DESIGN.md`, `STITCH.md`, and relevant `docs/design-specs/*` before proposing implementation.

## Stop Conditions

Stop and re-plan when:

- Two attempts fail with the same approach.
- A new P0/P1 appears outside scope.
- Agent ownership overlaps with another active session.
- Production data contradicts the current RCA.
- The user says to stop, slow down, not edit, or not commit.

Do not continue a loop just because the model can generate another plan.

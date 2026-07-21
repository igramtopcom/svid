# Review Verdict Protocol

## Verdicts

`SIGN-OFF`

- No release-blocking issue found.
- Non-blocking notes may still be listed as follow-ups.

`SIGN-OFF WITH ASSUMPTIONS`

- Releaseable if stated assumptions are accepted.
- Use when data was verified by another named session/team, or when the reviewer lacks access but code consequences are clear.

`BLOCK RELEASE`

- Only for P0/P1.
- Must include evidence, user impact, release consequence, and minimal fix path.

`FOLLOW-UP`

- P2/P3, cleanup, observability, uncertainty, naming, test expansion, or future hardening.
- Must not block release by itself.

## Finding Format

```md
Severity: P0 | P1 | P2 | P3
Verdict impact: BLOCK RELEASE | FOLLOW-UP
Evidence:
User impact:
Release consequence:
Minimal fix path:
Assumptions:
```

## Rules For Codex Review

- Review code consequences, not the social status of another agent.
- If Claude has production data access and Codex does not, Codex may challenge consistency but must not reject the data solely due to lack of local access.
- A caveat is not a blocker.
- A better architecture is not a blocker unless the current change introduces a P0/P1 release risk.
- Prefer one decisive verdict over a long hedge.

## Rules For Claude Builder

- Do not blindly accept Codex.
- For each finding, answer with `ACCEPT`, `REJECT WITH EVIDENCE`, `DEFER`, or `ASK HUMAN`.
- Fix only the minimal release-blocking issue unless the task packet allows broader work.
- After fixing, produce a new proof pack and ask for a focused re-review.

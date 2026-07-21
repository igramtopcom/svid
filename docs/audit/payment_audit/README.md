# Payment subsystem audit — 2026-05

Comprehensive audit of the Stripe / crypto payment subsystem on the Go
backend (`backend/internal/premium/`). Triggered by a yearly subscription
license that received a 2-year `expires_at` value
([investigation thread](#)).

## Layout

```
docs/audit/payment_audit/
├── README.md         ← this file
├── fix_plan.md       ← living plan for Wave 0–3; the source of truth
└── reviews/
    ├── claude_initial_findings.md     ← first-pass audit, my (Claude) side
    ├── codex_initial_findings.md      ← first-pass audit, Codex CLI side
    ├── w0_pre_final.md                ← Codex final pre-review of Wave 0
    ├── w0_post_final.md               ← Codex final post-review of Wave 0
    ├── w1_pre_final.md                ← Codex final pre-review of Wave 1
    └── w1_post_final.md               ← Codex final post-review of Wave 1
```

The `_final.md` review files capture the round at which Codex converged on
`no-blockers` / `push-to-main`. Intermediate rounds are not committed
(they're iteration noise — the diffs they triggered are visible in the
git history of `fix_plan.md` and the source files).

## Two-gate review workflow

Each wave goes through this loop before the next wave starts:

1. **Pre-review** — Codex audits the plan section for the upcoming wave.
   Iterate plan amendments until Codex returns `no-blockers`.
2. **Implement** — write the code + tests. Run the integration suite.
3. **Post-review** — Codex audits the implementation against the plan.
   Iterate fixes until Codex returns `push-to-main` (or the explicit
   plan deviations it endorses).
4. **Push** — push to origin/main, verify production deploy SHA via
   `curl https://api.svid.app/health`.

Why two gates: pre-review catches plan-level bugs (security holes,
hidden dependencies, missing fixtures) before any code is written.
Post-review catches implementation-level bugs (race conditions, error
swallowing, plan-vs-impl deltas). The dual-agent (Codex + Claude)
shape forces explicit disagreement to surface — if both agents land
in the same place independently, the call is well-grounded.

## Wave status

| Wave | Scope | State | SHA |
|------|-------|-------|-----|
| W0   | Postgres-backed webhook integration test infrastructure | ✓ Shipped 2026-05-20 | `2ea6d6c1` |
| W1   | Critical: security + active-fraud (4 findings) | ✓ Shipped 2026-05-21 | `f676f706` / `dc8285b9` |
| W2   | Money correctness (7 findings) | Pending pre-review | — |
| W3   | Defensive cleanup (4 findings) | Pending pre-review | — |

## Cross-cutting impact

Desktop-app touchpoints from this audit are tracked separately:
`memory/payment_audit_app_impact.md` in the per-user Claude memory store
(not in this repo). Items that landed in the desktop app source live in
the standard `lib/` tree and ship via the regular release CI.

## Workflow notes

- The plan (`fix_plan.md`) is the **living** source of truth. Each
  Codex pre-review may amend it before implementation starts. Diffs to
  the plan are visible via `git log -p docs/audit/payment_audit/fix_plan.md`.
- Backfill tools live in `backend/cmd/` (`backfill_invoice_pi`,
  `backfill_license_expiry`, `cleanup_invoices`) and follow the
  dry-run / JSONL-backup / `--confirm` pattern documented in
  `memory/maintenance_tools.md`.
- Pre-deploy SQL gates required by Wave 2 / Wave 3 items are listed
  inline in `fix_plan.md` under each finding's deploy-risk section.

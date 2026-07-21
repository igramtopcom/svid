# Task Packet Template

Copy this before starting any non-trivial Claude/Codex workflow.

```md
## Mission

What exact outcome should be true when this task is done?

## Scope

Files, subsystems, brands, platforms, and user flows included.

## Out Of Scope

Explicitly list what must not be touched.

## Authority

- Product/release authority:
- Data authority:
- Builder:
- Reviewer:

## Success Criteria

- User-visible behavior:
- Code behavior:
- Tests/gates:
- Documentation/handoff:

## Known Risks

- Production:
- Payment/license:
- Release:
- UI/UX:
- Dirty tree:

## Allowed Autonomy

- Read-only allowed:
- Edits allowed:
- Commands allowed:
- Requires approval:

## Stop Condition

When must the agent stop and ask/re-plan?

## Required Proof

- File/line proof:
- Test/build proof:
- Runtime/production proof:
- Assumptions:

## Release Gate

Can this task push, tag, register release, force-update, or mutate production?

Default: no.
```

# Production Hardening Sign-Off

Use this sheet after `bash scripts/verify_production_readiness.sh 5` passes on the current branch tip.

## Preconditions
- Latest readiness report file:
- `git status` reviewed for unrelated dirty files:
- Baseline brand restored to `svid`:

## Svid
| # | Scenario | Expected | Pass/Fail | Notes |
| --- | --- | --- | --- | --- |
| 1 | Open a local video, then play, pause, and seek | No crash, no red screen, playback state stays correct |  |  |
| 2 | Close fullscreen player, reopen same media | Resume prompt appears only for meaningful progress |  |  |
| 3 | Fullscreen -> mini -> fullscreen | Progress/completion tracking continues across transfer |  |  |
| 4 | Fullscreen -> PiP/system PiP -> `Back to App` / `Open Player` / `Close` | Latest resume point persists across each exit path |  |  |
| 5 | Subtitle search: change language, search, close quickly | No `setState()` after dispose or UI freeze |  |  |
| 6 | External subtitle scan on first open | UI stays responsive during initial scan |  |  |
| 7 | Start trim or conversion, then cancel mid-run | Final status is `cancelled`, not `failed` |  |  |

## VidCombo
| # | Scenario | Expected | Pass/Fail | Notes |
| --- | --- | --- | --- | --- |
| 1 | Launch cold app start | Startup feels normal; no brand drift or missing premium bootstrap |  |  |
| 2 | Queue 2-3 downloads | Jobs dispatch without duplicate starts |  |  |
| 3 | Retry one failed job | Queue continues using available slots |  |  |
| 4 | `Pause all`, `Resume all`, `Cancel` on queued and active jobs | Queue state stays consistent and UI remains smooth |  |  |
| 5 | Compact queue `previous/next` and natural auto-advance | Queue continuity survives compact surfaces unless media surface changes |  |  |
| 6 | Fullscreen -> mini/PiP -> reopen current media | Latest meaningful resume point persists |  |  |

## Verdict
- `Pass`: both brands passed all critical scenarios with no material notes
- `Fail`: at least one scenario reproduced a real runtime bug
- `Not enough evidence`: scenarios were not executed or results are ambiguous

Final verdict:
- Branch status:
- Follow-up bug commits, if any:

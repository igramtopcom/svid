# SSvid Landing — Verification Protocol

Date: 2026-04-24
Owner: Verification CTO (peer, gate layer)

## Mục Đích

Giao thức phối hợp giữa hai agent cùng làm việc trên `ssvid.app`:

- **Landing CTO chính** — implementation: narrative, IA, code, template, build.
- **Verification CTO (tôi)** — gate layer trước commit: static audit, build audit, runtime production-parity, deploy-readiness verdict.

Nguyên tắc: **không ai commit vào `website/` cho đến khi Verification CTO ra verdict PASS**. Dirty files tích lũy tự do trong working tree. Commit là thời khắc đi qua gate.

## Phân Vai (Tuyệt Đối Không Chồng Chéo)

| Hành động | Landing CTO chính | Verification CTO |
|-----------|-------------------|------------------|
| Sửa `.html`, `.css`, `.js`, templates, `build.js` | YES | NO |
| Sửa `website/src/`, `website/assets/` | YES | NO |
| Quyết định narrative, copy, IA | YES | NO |
| Chạy `node build.js`, run dev server | YES | YES (read-only purposes) |
| Viết `website/docs/landing-*.md` (baseline, narrative) | YES | NO |
| Viết `website/docs/verification-*/...` | NO | YES |
| Viết `scripts/verify-landing/...` | NO | YES |
| Chạy Playwright production-parity test | NO | YES |
| `git commit` | chỉ khi verdict PASS | chỉ commit vào verification artifacts của chính mình |

Vi phạm phân vai = flag ngay trong verdict.

## Handshake States

Mỗi lần Landing CTO hoàn thành một checkpoint (xong 1 Step của baseline, hoặc muốn pre-verify trước commit), đi qua 4 state:

```
REQUESTED → VERIFYING → { PASS | FAIL } → (nếu FAIL) → REWORK → REQUESTED → ...
```

### State 1 — REQUESTED

Landing CTO tạo file:

```
website/docs/verification-requests/step{N}-{slug}.md
```

Nội dung tối thiểu:

- Step name và mapping về baseline (ví dụ: "Step 1 — lock homepage message spine")
- Danh sách files đã modify (grep `git status`)
- Danh sách files đã xóa/add
- Self-assessment ngắn: tự chấm theo 7 Decisions của baseline
- Acceptance criteria bạn nghĩ nên áp dụng

### State 2 — VERIFYING

Verification CTO pick up request, chạy pipeline 4 layer:

1. Static audit — `scripts/verify-landing/audit-static.sh`
2. Build audit — `scripts/verify-landing/audit-build.sh`
3. Runtime production-parity — `scripts/verify-landing/audit-runtime.sh`
4. Deploy-readiness verdict — `scripts/verify-landing/deploy-readiness.sh`

Không trả lời cho đến khi cả 4 layer chạy xong (trừ khi layer trước fail nghiêm trọng, early exit).

### State 3 — PASS hoặc FAIL

Verification CTO viết verdict:

```
website/docs/verification-reports/step{N}-{slug}-verdict.md
```

Cấu trúc verdict:

- Overall: PASS / FAIL / CONDITIONAL PASS
- Scorecard per baseline Decision (1-7): % điểm
- Blocking issues: list, mỗi item có file + line + lý do
- Non-blocking observations: list
- Recommendation: cho commit / cho commit sau khi fix X / không cho commit

PASS = xanh để commit. FAIL = không commit. CONDITIONAL PASS = commit được sau khi fix N items cụ thể (Landing CTO tự fix rồi tạo re-request, không cần full cycle lại).

### State 4 — REWORK

Nếu FAIL, Landing CTO fix → tạo file mới:

```
website/docs/verification-requests/step{N}-{slug}-rework-{M}.md
```

Verification CTO re-verify. Vòng lặp cho đến khi PASS.

## Cheap Re-run Design

Verification scripts phải idempotent + cheap để chạy nhiều lần:

- Static audit < 10s
- Build audit < 30s
- Runtime audit < 120s
- Deploy-readiness tổng < 3 phút

Landing CTO có thể tự chạy `scripts/verify-landing/audit-static.sh` bất cứ lúc nào như sanity check trước khi gửi request chính thức. Verification CTO không ghét re-run.

## File Locations

```
website/docs/
├── landing-cto-baseline-2026-04-24.md           # Baseline decisions (Landing CTO)
├── landing-cto-peer-review-2026-04-24.md        # Peer review (Verification CTO)
├── verification-protocol.md                      # This file
├── verification-requests/                        # Request từ Landing CTO
│   └── step{N}-{slug}.md
├── verification-reports/                         # Verdict từ Verification CTO
│   ├── step{N}-{slug}-verdict.md
│   └── YYYY-MM-DD-passN-*.md                    # Periodic snapshots
└── landing-scorecard-latest.md                   # Current score (auto-updated)

scripts/verify-landing/
├── README.md
├── audit-static.sh
├── audit-build.sh
├── audit-runtime.sh
└── deploy-readiness.sh
```

## Commit Authority

Verification CTO **tự commit** artifacts của chính mình (docs + scripts trong phạm vi table "phân vai") mà không cần gate qua chính mình — vì đó là output verification, không phải production code.

Landing CTO **không commit gì** cho đến verdict PASS.

Chairman là final authority: có thể override verdict PASS/FAIL với lý do ghi rõ.

## Emergency Deploy

Nếu có bug production cần hotfix khẩn, Chairman có thể bypass protocol. Verification CTO vẫn phải post-mortem audit sau khi hotfix đã deploy, và ghi nhận debt.

## Kết

Protocol này không phải bureaucracy. Nó là cách duy nhất để hai agent không dẫm chân, cùng đẩy landing page lên chuẩn industry-standard mà Chairman đặt ra.

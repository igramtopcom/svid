# macOS QA Checklist — Installer/Native Waves 1–11

**Purpose.** Delegatable validation pass for the hardening waves shipped
between commit `401f5493` and `ce375085` on the macOS side. Any tester
with a Mac (Apple Silicon or Intel, macOS 13+) can follow this list and
report green / red per scenario — the Installer/Native CTO's own host
has already exercised every automatable surface, this list covers what
only a human in front of a Mac can observe.

Two parts:

1. **Automated** — `scripts/macos_qa_smoke.sh` covers the machine-
   verifiable gates (codesign, notarize, entitlements tight, quarantine
   xattr, launch smoke, binary cache).
2. **Manual** — this document covers what a script cannot verify
   (Gatekeeper first-open UX, WebView JS after entitlement tighten,
   auto-update end-to-end, cloud-sync side effects).

Run the automated pass first; the manual pass only makes sense if the
automated pass is fully green.

---

## Machine profile

Before starting, confirm:

- [ ] macOS 13 Ventura or newer (14+ preferred for Smart App Control
      parity expectations)
- [ ] Gatekeeper **enabled** (System Settings → Privacy & Security →
      Security → "App Store and identified developers")
- [ ] First-time install on this user account — no prior `com.svid.app`
      or `com.tinasoft.vidcombo` app data
- [ ] Network can reach `github.com` (binary CDN),
      `ffmpeg.martin-riedl.de`, `api.svid.app`, `api.vidcombo.net`
- [ ] **No corporate SSL-scanning proxy** — that intercepts binary
      downloads and produces confusing CERTIFICATE_VERIFY_FAILED
      failures that look like app bugs but are infra issues

## Artefacts

From the GitHub release or a signed CI artefact:

- `Svid-<version>-macos-universal.dmg`
- `VidCombo-<version>-macos-universal.dmg`

Do NOT pre-open or `xattr -c` these — the quarantine bit and Gatekeeper
UX are part of what we validate.

---

## Scenario 1 — Fresh install, Svid

1. Run the automated harness (skip-launch first to verify static gates):

   ```bash
   bash scripts/macos_qa_smoke.sh --dmg <path-to-svid.dmg> --brand svid --skip-launch
   ```

   - [ ] M0–M6 all PASS (bundle identity, codesign, stapler ticket,
         spctl accepted, Release entitlements tight, no lingering
         quarantine on the mounted .app)

2. Now exercise launch:

   ```bash
   bash scripts/macos_qa_smoke.sh --dmg <path-to-svid.dmg> --brand svid
   ```

   - [ ] M7 launch PASS (boot markers observed within 45s)
   - [ ] M8 bindir PASS (3 binaries downloaded + sane sizes)

3. Double-click the DMG in Finder:

   - [ ] Finder shows the Svid icon (Nocturne Cinematic red) — NOT a
         generic Flutter placeholder
   - [ ] Drag to Applications completes with no Gatekeeper warning
   - [ ] First open from Applications: single "This app is from the
         Internet" prompt (expected once), NOT "developer cannot be
         verified" (would indicate stapling/notarize regression)

4. First launch UX (fresh user, no binaries yet):

   - [ ] Splash/first-frame appears ≤ 1.5s (per Wave 7 startup profiler
         baseline: 425–634ms historical)
   - [ ] Binary provisioning UI progresses (yt-dlp / ffmpeg / gallery-dl
         downloads with visible progress)
   - [ ] NO persistent keychain entitlement warning in system logs:
         `log show --predicate 'process == "svid"' --last 5m |
          grep -i entitlement` should show zero `-34018` errors
         (Wave 1 keychain probe fallback engaged)
   - [ ] Tray icon appears in the menubar (Arctic Blue crown for
         VidCombo, Wine Red for Svid)

5. Paste a YouTube URL, extract, download one video:

   - [ ] Extraction succeeds
   - [ ] Quality selector populates with MP4 formats
   - [ ] Download writes to `~/Downloads` without permission dialog
   - [ ] File opens in macOS Quick Look (sanity: not a text stub)

## Scenario 2 — Fresh install, VidCombo, no legacy install

Same as Scenario 1 but targeting `VidCombo-*.dmg`. Additional checks:

- [ ] Tray icon is Arctic Blue (not Wine Red)
- [ ] `~/Library/Application Support/com.tinasoft.vidcombo/bin/` gets
      populated (NOT the Svid bundle id)
- [ ] Free-tier limit reflects PHP backend (10 downloads/day), not the
      Go-backend 15/day svid default

## Scenario 3 — WebView JS under tight entitlements (W1 critical)

The Wave 9839f674 tighten removed `allow-jit`. WebKit's JavaScriptCore
falls back to interpreter mode without JIT. This scenario confirms JS
still works, just slower — and that no critical flow outright breaks.

1. Launch the app.
2. Open the in-app browser (the Discover tab).
3. Navigate to `youtube.com`, log into a test Google account:

   - [ ] Login page loads
   - [ ] Password field accepts input
   - [ ] 2FA (if enabled on test account) completes
   - [ ] Cookies persist after login (WebView2-equivalent on macOS is
         WKWebView — verify a subsequent "Paste URL" operation inherits
         auth state)

4. Navigate to `facebook.com`, `instagram.com`, `x.com`:

   - [ ] Each site renders (slow JS is expected; broken rendering is
         NOT — would indicate WebKit sandbox / entitlement regression)

If any site refuses to load or shows a JS console error the tester can
see, capture a screenshot + the `log stream --predicate 'process ==
"com.apple.WebKit.WebContent"' --level info --last 1m` output and
escalate — that's the class of regression W1 entitlement tighten would
trigger.

## Scenario 4 — Auto-update end-to-end (W3 + W6 + W8)

Hardest scenario to set up (needs an older release tag installed).

Prerequisites:

- Install a previous-tag release first (e.g., v1.3.4)
- Ensure backend has a newer release registered (so update check
  fires)

Steps:

1. Open the old-version app. Trigger "Check for updates".
2. Observe:

   - [ ] Download progress bar moves smoothly
   - [ ] **Pull the Wi-Fi plug mid-download for 10s, then restore**
   - [ ] Download RESUMES from the byte count it reached, does NOT
         restart from 0 (Wave 3 Range-resume)
   - [ ] "Verifying integrity" step completes without a crash even if
         the installer is 100MB+ (Wave 3 streaming SHA-256)
   - [ ] "Install now" closes the current app, mounts the new DMG,
         copies the app, relaunches with new version within 60s

3. After relaunch:

   - [ ] Premium status, library entries, and settings persist
   - [ ] No stray keychain re-migration warning
   - [ ] Tray icon reappears

## Scenario 5 — Corrupted download (W6 supply-chain)

Simulate a tampered yt-dlp download to verify the SHA256 gate:

1. Delete `~/Library/Application Support/com.svid.app/bin/yt-dlp`.
2. Open a dev build with `BinaryInfo._ytDlpChecksumsUrl` temporarily
   pointed at a static fixture that returns a WRONG hash.
3. Trigger an extraction:

   - [ ] Download fails with "Integrity verification failed" user-
         visible message
   - [ ] Corrupt file DELETED from disk, not left dangling
   - [ ] App stays functional (doesn't hard crash)

## Scenario 6 — VidCombo legacy migration (mac)

If a tester has a working old VidCombo install with media files at
`~/Documents/VidCombo/` or `~/Downloads/VidCombo/`:

1. Install the new VidCombo DMG.
2. First launch:

   - [ ] Library tab shows the legacy files with filename-derived
         titles
   - [ ] No "legacy import" modal / spinner stalls startup (it's
         background-import per Wave 5)
   - [ ] `~/Documents/VidCombo/` files are NOT deleted — the old
         library remains in place on disk

## Scenario 7 — Restart / lifecycle

1. Open the app, paste a URL, start a download.
2. **Quit via Cmd+Q** mid-download.
3. Reopen:

   - [ ] Download resumes or shows a paused state (not "failed")
   - [ ] No orphan yt-dlp process in Activity Monitor
         (Rust download manager terminal-task sweep)

4. Close with window-X (not Cmd+Q). Relaunch:

   - [ ] Tray icon persists, clicking restores window
   - [ ] Window position / size restored per Wave-8 profiler

---

## Report format

After each scenario:

```
Scenario N — PASS | FAIL | PARTIAL
Machine: macOS <version>, chip <Apple Silicon | Intel>, Gatekeeper <on/off>
Observations:
  - ...
Failures:
  - ... (with log excerpts)
Attachments:
  - screenshots/
  - `log show --predicate 'process == "<exe>"' --last 5m` output
  - harness stdout
```

Post to the release tracking issue on `mydinh-studio/svid-desktop` with
label `macos-qa`.

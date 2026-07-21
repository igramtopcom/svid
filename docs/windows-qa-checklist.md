# Windows QA Checklist — Installer/Native Wave 1-6

**Purpose.** Delegatable validation pass for the hardening waves shipped
in this repo between commit `401f5493` and `f16b3ed4`. Any tester with a
Windows 11 machine (Smart App Control ON for full coverage) can run this
list and report a green/red result per scenario — the Installer/Native
CTO cannot close these gaps from a macOS build host.

Two parts:

1. **Automated** — `scripts/windows_qa_smoke.ps1` covers the machine-
   verifiable gates (signing, registry, marker files, silent-install
   relaunch).
2. **Manual** — this document covers everything a script cannot check
   (Smart App Control UX, WebView login flows, visual icon rendering,
   etc.).

Run the automated pass first; the manual pass only if the automated pass
is fully green.

---

## Machine profile

Before starting, confirm:

- [ ] Windows 11 22H2 or newer
- [ ] Smart App Control **ON** (Settings → Privacy & Security → Smart App
      Control)
- [ ] Windows Defender real-time protection **ON**
- [ ] User is a **non-administrator** standard account (elevate via UAC
      when prompted)
- [ ] Network can reach `github.com`, `ffmpeg.martin-riedl.de`,
      `api.ssvid.app`, `api.vidcombo.net`
- [ ] **No VPN** (corporate SSL-scanning proxies trip the binary TLS
      handshake; run clean first, then retry under VPN as a separate
      scenario)

## Artefacts to obtain

From the GitHub release page **or** a signed CI artefact:

- `SSvid-<version>-windows-x64-setup.exe`
- `VidCombo-<version>-windows-x64-setup.exe`

Do not `xattr -c` / Unblock-File these — the Zone.Identifier ADS check
below needs them marked-of-web as a real user would receive them.

---

## Scenario 1 — Fresh install, SSvid, new machine

**Precondition:** no SSvid installed, no VidCombo installed, no legacy
BLUEBYTE VidCombo entries.

1. Run the automated harness:

   ```powershell
   pwsh -File scripts/windows_qa_smoke.ps1 `
        -Installer <path-to-ssvid-setup.exe> -Brand ssvid
   ```

   - [ ] All gates PASS / SKIP (no FAIL, no WARN on W3.3 RSA check)

2. Right-click the installer → Properties → confirm **Digital
   Signatures** tab shows a valid RSA signature from `Bui Xuan Mai`
   (Sectigo IV).

3. Double-click the installer — confirm:

   - [ ] Smart App Control **does NOT block** the installer
   - [ ] UAC prompt shows the correct publisher name (not "Unknown
         publisher")
   - [ ] Setup wizard completes without error

4. First launch:

   - [ ] App icon in taskbar is the SSvid icon (not the default Flutter
         icon or a generic chrome rectangle)
   - [ ] App window renders the Nocturne Cinematic theme within ~3s of
         double-click
   - [ ] System tray icon appears and clicking it restores the window
   - [ ] Open Settings → Downloads — "Download location" reads the OS
         Downloads folder (not an empty string)

5. Paste a YouTube URL into the URL bar — confirm:

   - [ ] Extraction starts within ~10s (gallery-dl / yt-dlp / ffmpeg all
         download from GitHub on first run — this can take up to 2 min
         on first install)
   - [ ] No "SSL certificate verification failed" dialog
   - [ ] Quality selector populates with at least one MP4 format
   - [ ] Clicking Download writes a file to the Downloads folder

## Scenario 2 — Fresh install, VidCombo, NO legacy BLUEBYTE install

Same as Scenario 1, substituting VidCombo brand. Additional checks:

- [ ] Tray icon is the VidCombo Arctic Blue variant (not SSvid red)
- [ ] First launch contacts `api.vidcombo.net/checkkey.php` (visible in
      Fiddler/Wireshark if hooked up)
- [ ] Free-tier limit is **10 downloads/day**, not 15

## Scenario 3 — VidCombo migration from BLUEBYTE install

**Precondition:** a machine with a working BLUEBYTE VidCombo install
that has an active premium license stored.

1. Record the license key from the old VidCombo Settings page (for
   manual cross-check).
2. Run the automated harness with the `-BluebyteLegacyExe` flag pointed
   at the old uninstaller:

   ```powershell
   pwsh -File scripts/windows_qa_smoke.ps1 `
        -Installer <path-to-vidcombo-setup.exe> -Brand vidcombo `
        -BluebyteLegacyExe 'C:\Program Files (x86)\VidCombo\unins000.exe'
   ```

   - [ ] W5.1 PASS — legacy entry detected
   - [ ] W5.2 PASS — installer-ran marker written
   - [ ] W5.3 PASS — license key extracted to `%TEMP%\vidcombo_migrated_key.txt`
   - [ ] W5.4 PASS — old BLUEBYTE entry removed from registry

3. First launch of the new VidCombo:

   - [ ] Premium badge appears in Settings → Premium (license imported
         from `%TEMP%\vidcombo_migrated_key.txt`)
   - [ ] Download limit reads as Premium (not free-tier)
   - [ ] `%TEMP%\vidcombo_migrated_key.txt` is **deleted** after the
         app consumes it (prevents re-import on reinstall)
   - [ ] Legacy library files in `~/Documents/VidCombo/` and
         `~/Downloads/VidCombo/` appear in the Library tab

4. Force-uninstall case (simulates Defender locking the installer-ran
   marker):

   - [ ] Restart the machine with the marker file still on disk (copy
         it back to `%TEMP%` before reboot if the app deleted it)
   - [ ] Launch app three times
   - [ ] Confirm premium status does NOT disappear on the 3rd launch
         (marker fingerprint must catch the anti-loop scenario — Wave 5.2
         bug fix)

## Scenario 4 — Auto-update (in-app)

**Precondition:** a running app at a lower version than the release
artefact. Easiest path: install a previous-tag release first, then point
`lib/core/services/startup_service.dart`'s update check at the new
release via the backend flag.

1. Open the running app and trigger the "Check for updates" action.
2. Confirm:

   - [ ] The new version is downloaded with a progress bar that moves
         past 0% (streaming download works — Wave 3 fix)
   - [ ] If the network is interrupted mid-download, **retrying resumes
         from the byte count instead of restarting** (HTTP Range resume —
         Wave 3 fix). Simulate by disconnecting Wi-Fi for 10s during the
         download.
   - [ ] Integrity-check step shows without a crash
   - [ ] "Install now" closes the current app, runs the silent installer,
         and **automatically reopens the new version within 60 seconds**
         (Inno Setup dual `[Run]` — Wave 3 fix). *This is the single
         highest-impact regression to catch: the old installer silently
         failed to relaunch.*
   - [ ] Premium status, library entries, and settings persist
         across the upgrade

## Scenario 5 — Corrupted-binary / checksum-failure simulation

**Precondition:** a way to force the binary download to fail integrity
check. Easiest: point `lib/core/binaries/binary_info.dart`'s
`_ytDlpChecksumsUrl` at a static fixture manifest that lists a wrong
hash, or use a test environment with a local manifest.

1. Delete `%LOCALAPPDATA%\ssvid\bin\yt-dlp.exe`.
2. Trigger a download inside the app — forces a yt-dlp re-download.
3. Confirm:

   - [ ] Download fails with a user-visible message mentioning
         **"Integrity verification failed"** (Wave 2/6 supply-chain gate)
   - [ ] The corrupt file is **deleted** — not left on disk to be picked
         up on the next launch
   - [ ] No user-impacting crash; the extraction UI recovers

## Scenario 6 — chmod / hardened-runtime failure surfaces (N/A on Windows)

Skip — this is a macOS-specific gate (Wave 2 chmod-propagation fix). See
the macOS checklist.

## Scenario 7 — Smart App Control edge cases

1. Disable Smart App Control, install, then re-enable — confirm the
   already-installed app still launches.
2. With Smart App Control **ON**, install a **debug-signed** build (no
   Developer ID) — confirm SAC BLOCKS the launch and reports the
   publisher as unknown. This is the expected failure mode and proves
   SAC is working; it also demonstrates why the Wave 3 RSA-signing gate
   is a release blocker, not a suggestion.

---

## Report format

After each scenario, record:

```
Scenario N — PASS | FAIL | PARTIAL
Machine: Windows 11 <build>, Defender <on/off>, SAC <on/off>
Observations:
  - ...
Failures:
  - ...
Attachments:
  - screenshots/
  - Event Viewer export (filtered to the app process)
  - harness output JSON
```

Post the report to the release tracking issue on `mydinh-studio/ssvid-desktop`
under the label `windows-qa`.

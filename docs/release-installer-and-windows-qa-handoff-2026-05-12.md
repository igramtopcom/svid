# Installer, Signing, Notarization, and Windows QA Handoff

Date: 2026-05-12

Purpose: preserve the current release-engineering context for future
agents/reviewers. This is an internal handoff, not public release notes.

Scope:

1. Installer, certificates, signing, notarization, and release gates.
2. Mac-controlled Windows QA orchestration.

Do not store Windows QA passwords or signing PINs in this document.

## Executive Status

Current direction:

- Windows release signing is moving from ECC to RSA 3072.
- This direction is correct for the Windows desktop ecosystem because
  Smart App Control currently allows RSA-based code-signing certificates
  and does not currently support ECC signatures.
- The technical direction is not the same as "all artifacts are ready".
  The release process still requires real installer execution smoke tests.

Current important commits:

- `20bcf4b4`: added Windows installer execution smoke gate to CI.
- `015c820a`: fixed smoke wait behavior and made `WebView2Loader.dll`
  missing a hard failure.
- `957c2f64`: made `windows_qa_smoke.ps1` ASCII-only and fixed stale
  `WaitForExit` comments.

Current artifact findings from the Windows QA machine:

- `Svid 1.3.9` Windows installer EXE: FAIL. Real Windows dialog:
  "The setup files are corrupted. Please obtain a new copy of the program."
- `Svid 1.3.9` portable ZIP: PASS. Runtime payload is Authenticode-valid,
  RSA OID, x64, and launches.
- `VidCombo 1.6.6` Windows installer EXE: PASS on Windows 10 QA. Clean
  install, installed payload scan, critical DLL scan, launch, and WER check
  were green.
- `Svid 1.3.8` RSA hotfix installer control sample: wizard opens. This
  proves the Windows QA machine and harness can execute an Svid Inno
  installer correctly.

Current release verdict:

- Do not publish the `Svid 1.3.9` Windows installer artifact that failed
  real execution.
- `VidCombo 1.6.6` is a strong candidate from installer/runtime smoke, but
  still needs the intended release approval path.
- The next safe validation step is a dry-run acceptance dispatch for `svid`
  on commit `957c2f64` to prove the new CI smoke gate catches or clears this
  class of issue before release publishing.

## Area 1: Installer, Certs, Signing, Notarization

### Strategic Decision: ECC -> RSA

Windows production signing baseline:

- Required algorithm: RSA.
- Current key size baseline: RSA 3072.
- Current publisher identity observed in signed artifacts:
  `CN=Bui Xuan Mai, O=Bui Xuan Mai, S=Thai Binh, C=VN`.
- Current issuer observed in signed artifacts:
  `Sectigo Public Code Signing CA R36`.
- RSA public key OID used by smoke gates:
  `1.2.840.113549.1.1.1`.
- ECC public key OID that must not pass production signing:
  `1.2.840.10045.2.1`.

Why RSA:

- Microsoft Smart App Control documentation states that SAC allows
  applications signed with RSA-based digital certificates and does not
  currently support ECC signatures.
- Microsoft Smart App Control FAQ says SAC falls back to checking for a
  valid signature when the cloud service cannot make a confident prediction.
- Therefore, ECC-signed Windows desktop release artifacts are a dead-end for
  SAC compatibility even if they work on some machines today.

References:

- Microsoft Learn, Smart App Control code signing:
  https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control
- Microsoft Support, Smart App Control FAQ:
  https://support.microsoft.com/en-us/windows/smart-app-control-frequently-asked-questions-285ea03d-fa88-4d56-882e-6698afdb7003
- Local repo policy:
  `docs/windows-signing-policy.md`
- Local migration runbook:
  `docs/windows-ecc-to-rsa-migration.md`

### Pipeline Shape

Expected Windows pipeline topology:

1. Build unsigned Windows runtime bundle on Windows runner.
2. Sign all runtime PE files on the macOS YubiKey runner.
3. Build the portable ZIP from the signed runtime bundle.
4. Build the Inno installer from the signed runtime bundle.
5. Sign the outer Inno installer EXE on the macOS YubiKey runner.
6. Run `windows-installer-smoke` on `windows-latest` against the final signed
   artifact.
7. Only after smoke passes may `create-release` publish non-dry-run releases.

Important invariant:

- `dry_run=true` means no GitHub Release publish, no public release-asset
  clobber, no backend registration, and no auto-update fire.
- A test build for humans must come from GitHub Actions artifacts, not from
  overwriting public release assets.

### CI Hardening Already Added

Signing-slot hardening:

- Removed silent `9a` fallback.
- Production workflows must explicitly set `WINDOWS_SIGNING_PIV_SLOT`.
- Current production convention is `9c` for the RSA signing cert.
- ECC is fail-hard by default in production signing scripts.
- `WINDOWS_SIGNING_ALLOW_ECC=1` is diagnostic-only and must not be set in CI.

Runtime payload hardening:

- Installed payload scan requires all runtime PE files to be:
  - Authenticode-valid.
  - RSA by public key OID `1.2.840.113549.1.1.1`.
  - x64 PE machine `0x8664`.
- Critical binaries:
  - app executable: hard fail if missing/invalid.
  - `native.dll`: hard fail if missing/invalid.
  - `WebView2Loader.dll`: hard fail if missing/invalid.
- Inno `unins*.exe` is tracked separately because current Inno uninstaller is
  not signed by default. It should not false-fail runtime payload checks.

Installer execution hardening:

- New `windows-installer-smoke` job runs after `sign-windows`.
- The smoke job downloads the final `${brand}-Windows` artifact and calls
  `scripts/windows_qa_smoke.ps1` once.
- `create-release` now depends on `windows-installer-smoke`.
- The smoke script:
  - Runs installer with `/CURRENTUSER /VERYSILENT /SP- /SUPPRESSMSGBOXES
    /NORESTART /CLOSEAPPLICATIONS /LOG=<temp-log>`.
  - Requires Inno log to exist and be non-empty.
  - Fails on corruption markers such as setup-files-corrupted, CRC, cyclic
    redundancy, or Bad Image.
  - Uses a poll loop instead of plain `WaitForExit`.
  - Kills an Inno `[Run]` auto-launched app once to unblock installer exit.
  - Re-launches the app deliberately for startup smoke.
  - Checks Windows Event Log / WER for application faults.
  - Cleans lingering app processes.
  - Is ASCII-only to avoid PowerShell 5.1 UTF-8 no-BOM parsing issues.

### Important Incidents and Lessons

Do not repeat these mistakes:

- Do not treat Authenticode verification as proof that an Inno installer opens.
  `Svid 1.3.9` was RSA Authenticode-valid but failed at installer startup with
  an Inno corruption dialog.
- Do not use `innoextract -t` as a release gate. It reported unsupported-loader
  style warnings for artifacts that opened and installed correctly on real
  Windows.
- Do not rely on a claimed `setup.exe /VERIFY` flag. It is not listed in the
  official Inno Setup command-line parameters.
- Do not claim "sign-after-compile is root cause" without evidence. The
  Svid unsigned outer installer control also failed, so signing was not
  proven as the root cause.
- Do not use public GitHub Release asset overwrite as a dry-run strategy.
  It is user-facing and destructive.
- Do not add direct Inno `[Code]` external DLL imports casually. The earlier
  `shell32.dll` import caused installer startup failure. Prefer less critical
  cosmetic behavior over a fragile installer entry point.

Inno command-line reference:

- https://jrsoftware.org/ishelp/topic_setupcmdline.htm

### Current Windows Artifact Test Matrix

Test machine:

- Windows version observed: Windows 10 `10.0.19045.6466`.
- This machine is valid for installer/runtime/signature smoke.
- This machine is not a Windows 11 Smart App Control final gate.

Results:

| Artifact | Result | Evidence |
| --- | --- | --- |
| `Svid-1.3.9-windows-x64-setup.exe` | FAIL | Real Windows dialog: setup files corrupted; silent install exit 1; no install log; no app install |
| `Svid-1.3.9-windows-x64.zip` | PASS | 28 PE files valid, RSA OID, x64; critical files pass; app launches 8 seconds |
| `VidCombo-1.6.6-windows-x64-setup.exe` | PASS | Clean install; Inno log success; 28 PE files valid, RSA OID, x64; app launches; no WER |
| `Svid-1.3.8 RSA hotfix installer` | PASS as control | Wizard opens on same Windows machine |

Local logs copied back during testing:

- `/private/tmp/clean-svid-smoke.log`
- `/private/tmp/clean-vidcombo-smoke.log`
- `/private/tmp/svid-zip-smoke.log`
- `/private/tmp/svid-installer-visible.png`

### macOS Signing and Notarization Context

macOS is a separate trust chain:

- macOS DMGs are signed with Apple Developer ID.
- Notarization staple validation passed for current dry-run macOS artifacts.
- Local Mac smoke previously verified:
  - DMG mount.
  - app launch.
  - visible window.
  - expected bundle ID and version.

Do not confuse macOS notarization success with Windows installer readiness.
They are independent gates.

### Current Acceptance Dispatch

Recommended acceptance test command:

```bash
gh workflow run release.yml --repo Luongxuongkho/svid-desktop \
  --ref feature/floating-capture-v2.2-state-machine \
  -f version=1.3.9 -f brand=svid \
  -f dry_run=true -f skip_tests=true
```

Interpretation:

- Smoke FAIL with corruption evidence: gate works and the Svid installer
  issue is reproducible in current CI.
- Smoke PASS: current pipeline and gate pass on the new commit. This does not
  prove the older corrupt artifact was transient bit-for-bit; it proves the
  current release lane is green.
- Smoke FAIL due harness bug: fix the harness before production release.

## Area 2: Mac-Controlled Windows QA Orchestration

### Goal

Use the MacBook as the primary orchestrator while the Windows PC acts as a
real Windows execution target. The operator should not need to manually drive
two machines for routine QA.

What Mac can control:

- Copy artifacts to Windows.
- Run PowerShell scripts on Windows through SSH.
- Start scheduled tasks inside the active Windows desktop session.
- Execute installers silently.
- Open installers visibly and capture screenshots.
- Scan installed payload signatures and PE architecture.
- Launch apps and inspect Windows Event Log / WER.

What still needs a real Windows UI or special environment:

- SmartScreen/SAC end-user UX.
- UAC confirmation if a task requires secure desktop approval.
- Windows 11 Smart App Control ON final validation.

### Current Windows Target

Current LAN target:

- IP: `192.168.31.75`
- SSH port: `22`
- SSH user: `qa`
- Credential: temporary QA credential, not stored in docs or git.
- Active console user observed in tasks: `User`
- Active profile path observed: `C:\Users\nguye`
- QA root:
  - `C:\QA\Snakeloader\artifacts`
  - `C:\QA\Snakeloader\scripts`
  - `C:\QA\Snakeloader\logs`

Current network facts:

- Mac reached Windows over SSH after moving onto the same `192.168.31.x`
  network.
- `ping` may fail even when SSH works. Use TCP check instead:

```bash
nc -vz -G 5 192.168.31.75 22
ssh qa@192.168.31.75 "whoami && hostname"
```

Security note:

- The `qa` account is a lab account with admin rights.
- Rotate or disable it after the release cycle.
- Do not commit the password.
- Defender exclusions added for `C:\QA\Snakeloader\artifacts` are test-lab
  convenience, not production security posture.

### SSH Is Not Enough for GUI Tests

SSH runs in a non-interactive context. Some installer/UI behavior is not
faithful there.

Use SSH for:

- File copy.
- Silent install scripts.
- Registry checks.
- Signature checks.
- Event log checks.

Use Scheduled Task with `/IT` for active desktop session tests:

```cmd
schtasks /Create /TN SnakeloaderSmoke ^
  /TR C:\QA\Snakeloader\scripts\run-smoke.cmd ^
  /SC ONCE /ST 23:59 /RU user /IT /F

schtasks /Run /TN SnakeloaderSmoke
```

This was required because visible installer tests and real app launch belong
to the active desktop session, not the SSH service session.

### Artifact Transfer Pattern

Copy from Mac to Windows:

```bash
scp /path/to/Svid-1.3.9-windows-x64-setup.exe \
  qa@192.168.31.75:C:/QA/Snakeloader/artifacts/

scp scripts/windows_qa_smoke.ps1 \
  qa@192.168.31.75:C:/QA/Snakeloader/scripts/
```

Copy logs back:

```bash
scp qa@192.168.31.75:C:/QA/Snakeloader/logs/clean-svid-smoke.log /private/tmp/
```

### Mark-of-the-Web and SmartScreen

Files copied by `scp` usually do not get the browser download
`Zone.Identifier` alternate data stream.

Implication:

- SCP-based tests are good for installer execution, Authenticode, payload scan,
  and launch.
- SCP-based tests are not faithful SmartScreen download UX tests.

For SmartScreen realism, either:

1. Download the installer through a browser on the Windows machine.
2. Add a `Zone.Identifier` stream manually for a test scenario.

Example:

```powershell
Set-Content -Path .\Svid-setup.exe -Stream Zone.Identifier -Value "[ZoneTransfer]`nZoneId=3"
```

Smart App Control final gate still requires Windows 11 with SAC ON.

### Local Build Lab Feasibility

The Windows PC currently works as a QA target, not a full local build lab.

Observed installed tooling:

- Present: Git, Windows PowerShell.
- Missing at time of check:
  - Flutter/FVM/Dart.
  - Rust/Cargo/MSVC toolchain.
  - CMake/Ninja.
  - Visual Studio Build Tools.
  - Inno Setup `iscc`.
  - Windows SDK `signtool`.
  - PowerShell 7.

Therefore, current best use:

- Build/sign through GitHub Actions or existing Mac/YubiKey lane.
- Copy artifacts to Windows.
- Run installer/runtime smoke on Windows.

Future local build-lab plan:

1. Install Flutter 3.29.3 or FVM.
2. Install Visual Studio Build Tools with Desktop C++ workload.
3. Install Rust MSVC toolchain.
4. Install CMake and Ninja.
5. Install Inno Setup.
6. Install PowerShell 7.
7. Keep production RSA signing on Mac/YubiKey unless a Windows-attached
   signing token or cloud signing path is explicitly approved.

Production-faithful local hybrid flow would be:

1. Windows builds unsigned runtime bundle.
2. Mac signs runtime PE files with YubiKey RSA.
3. Windows builds Inno installer from signed bundle.
4. Mac signs outer installer.
5. Windows executes final installer smoke.

### Operational Rules for Future Agents

Do:

- Treat Windows installer execution as mandatory, not optional.
- Use `windows_qa_smoke.ps1` as the single source of truth for automated
  Windows installer smoke.
- Keep logs and screenshots for failed installer attempts.
- Use OID-based RSA checks, not localized friendly-name guesses.
- Run visible-installer screenshot diagnostics when silent install fails before
  producing an Inno log.

Do not:

- Publish or clobber public GitHub Release assets as a test.
- Store Windows passwords or signing PINs in repo docs.
- Declare production-ready from Authenticode verification alone.
- Declare root cause from a single symptom without a control sample.
- Forget that Windows 10 QA cannot close Windows 11 SAC risk.

### Immediate Next Steps

1. Run the `957c2f64` acceptance dry-run for `svid`.
2. Inspect `windows-installer-smoke` result.
3. If smoke fails, download smoke log artifact and compare with the real
   Windows QA failure.
4. If smoke passes, run a follow-up dry-run for `vidcombo` or `both` only if
   release planning requires it.
5. Before any public Windows release, run Windows 11 SAC ON manual QA from
   `docs/windows-qa-checklist.md`.


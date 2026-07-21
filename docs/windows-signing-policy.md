# Windows Signing Policy

Applies to all Windows release artifacts for `SSvid` and `VidCombo`, including installer `.exe`, portable `.zip` payloads, and any shipped PE binaries (`.exe`, `.dll`).

## Purpose

Prevent Windows install and in-app update failures caused by non-compliant code-signing choices. This policy is the minimum acceptable standard for production Windows releases.

## Non-Negotiable Requirements

1. Windows release signing must use an Authenticode certificate backed by **RSA**.
2. Minimum key size for this repo is **RSA 3072**. Current baseline is **RSA 3072 on YubiKey** because the active Sectigo reissue flow rejects RSA 2048 for this order/template.
3. **ECC certificates are prohibited** for Windows release signing because Microsoft Smart App Control does not support ECC-signed apps.
4. Every shipped Windows PE file must be signed and timestamped:
   - installer `*-windows-x64-setup.exe`
   - app executable (`ssvid.exe` / `vidcombo.exe`)
   - native libraries such as `native.dll`
   - any future shipped updater/helper PE binaries
5. Windows payload signing must happen **before packaging**:
   - sign the runtime bundle first
   - build the portable ZIP from the signed bundle
   - build the installer from the signed bundle
   - sign the outer installer executable last
6. Publisher identity must stay stable across renewals or reissues unless there is explicit release approval and a migration plan.
7. Private keys must remain hardware-backed. No exportable production signing keys stored in the repo, CI secrets, or developer laptops.
8. Dedicated signing slots are preferred over reusing the PIV authentication slot. Current preferred target is **slot 9C**.
9. Sectigo key attestation submissions must use the **base64-encoded attestation chain** (`attestation.b64`), not raw PEM certificate text.

## Release Gates

1. CI preflight must fail if the signing certificate is not RSA or is expiring soon.
2. Release publishing must use the final signed Windows artifact output, never the unsigned bundle or intermediate packaging artifacts.
3. Manual QA for every Windows release must include:
   - Windows 11 fresh install with **Smart App Control ON**
   - installer launch + first app launch
   - upgrade from an existing installed version
   - in-app update from an older version to the new version
4. No Windows release tag may be published if any signing or Windows trust gate is red.
5. Legacy unsigned packaging paths are not release-eligible. In particular:
   - `.github/workflows/build-windows-test.yml` is deprecated
   - `scripts/package_windows.ps1` is legacy/manual-only and must not be treated as a production release flow

## Operational Rules

1. Reissue/rekey on the existing publisher identity is preferred over switching publisher names or certificate vendors.
2. Keep `AppId`, `AppName`, executable names, and installer upgrade path stable unless a separate migration is approved.
3. Do not overwrite production YubiKey slot material until the replacement certificate path is confirmed.
4. Any change to signing algorithm, certificate vendor, publisher subject, token slot, or CI signing flow requires:
   - doc update
   - dry run
   - Windows 11 Smart App Control validation

## Strategic Direction

Current production baseline: **Sectigo + YubiKey + RSA 3072**.
Preferred token layout: **slot 9C for Windows signing**; keep slot 9A free for authentication or legacy rollback during migration.

Longer-term target: evaluate **Microsoft Artifact Signing** for Windows to reduce hardware-token bottlenecks and align with Microsoft's preferred trust path. This is a future platform migration, not a blocker for the immediate RSA cutover.

## References

- Microsoft Smart App Control signing requirements:
  `https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control`
- Microsoft Smart App Control FAQ:
  `https://support.microsoft.com/en-us/windows/smart-app-control-frequently-asked-questions-285ea03d-fa88-4d56-882e-6698afdb7003`
- Yubico PIV / ykman commands:
  `https://docs.yubico.com/software/yubikey/tools/ykman/PIV_Commands.html`

# Windows ECC -> RSA Migration Runbook

This runbook migrates Windows release signing from the current ECC certificate to an RSA certificate without breaking the existing installer or upgrade path.

## Goal

- Restore compatibility with Windows 11 Smart App Control
- Keep `Svid` and `VidCombo` Windows upgrades stable
- Add guardrails so the same signing mistake cannot recur

## Success Criteria

1. New Windows artifacts are signed with **RSA 3072** and timestamped.
2. `bash scripts/preflight_yubikey.sh` passes on the signer machine.
3. Fresh install succeeds on Windows 11 with Smart App Control ON.
4. In-app update from an older Windows build succeeds.
5. Existing installed users keep their app data and upgrade path.

## Phase 0: Freeze and Prepare

- Pause new Windows release tags until RSA signing is ready.
- Keep the existing ECC-signed releases available; do not revoke them unless the key is compromised.
- Prepare test coverage:
  - Windows 10 machine
  - Windows 11 fresh install with Smart App Control ON
  - one machine with an older installed `Svid`
  - one machine with an older installed `VidCombo`
- Back up the current local signer materials:
  - `~/Desktop/yubikey-cert/leaf.pem`
  - `~/Desktop/yubikey-cert/sign_chain.pem`
  - `~/Desktop/yubikey-cert/secrets.txt`

## Phase 1: Confirm Reissue Path

1. Open a Sectigo support/reissue request for the current code-signing order.
2. Request the replacement certificate on the same publisher identity, but with an **RSA 3072** key.
3. Prefer staging the new key/cert in **slot 9C** so the legacy ECC material in `9A` remains available during migration.
4. Confirm the target YubiKey firmware supports RSA 3072. The active Sectigo reissue flow for this order rejects RSA 2048, so RSA 3072 is the repo baseline.

Notes:
- Buying a brand-new certificate is the fallback, not the first move.
- Keep publisher continuity if at all possible.

## Phase 2: Generate the New RSA Key on the YubiKey

Current repo automation originally signed from slot `9a`, but the repo now supports a configurable slot. The preferred migration path is to stage the RSA cert in **slot `9c`** first, then switch CI to that slot after validation.

This step writes new material to the chosen slot. Prefer an empty dedicated slot so we avoid destroying the current ECC setup in `9a`.

```bash
WINDOWS_SIGNING_KEY_ALGORITHM=RSA3072 \
YUBIKEY_PIV_SLOT=9c \
scripts/generate_windows_signing_csr.sh /tmp/windows-signing-rsa
```

Outputs:
- `windows-signing-9c.pub.pem`: public key generated on-device
- `windows-signing-9c.csr.pem`: CSR to send to Sectigo
- `windows-signing-9c.attestation.pem`: slot attestation certificate
- `windows-signing-9c.attestation-intermediate-f9.pem`: YubiKey attestation intermediate from slot `f9`
- `windows-signing-9c.attestation-chain.pem`: concatenated attestation cert + intermediate
- `windows-signing-9c.attestation.b64`: Sectigo-ready attestation payload

Important:
- Sectigo's `Key Attestation` field expects the contents of `attestation.b64`
- do **not** paste raw PEM certificates with `-----BEGIN CERTIFICATE-----` headers into the form

## Phase 3: Import the Reissued Certificate

After Sectigo returns the RSA certificate:

```bash
YUBIKEY_PIV_SLOT=9c scripts/import_windows_signing_cert.sh \
  /path/to/sectigo-rsa-leaf.pem \
  /path/to/sign_chain.pem
```

Then refresh the local cert files used by the signing scripts:

- replace `~/Desktop/yubikey-cert/leaf.pem`
- replace `~/Desktop/yubikey-cert/sign_chain.pem`

Verify the result locally:

```bash
openssl x509 -in ~/Desktop/yubikey-cert/leaf.pem -text -noout | \
  rg "Public Key Algorithm|Public-Key|Signature Algorithm|Subject:"
```

Expected result:
- `Public Key Algorithm: rsaEncryption`
- `Public-Key: (3072 bit)`

## Phase 4: Dry Run on the Signing Host

1. Run:

```bash
YUBIKEY_PIV_SLOT=9c bash scripts/preflight_yubikey.sh
```

2. Produce an unsigned Windows runtime bundle.
3. Sign the runtime bundle first.
4. Build the portable ZIP from that signed bundle.
5. Build the Inno Setup installer from that signed bundle.
6. Sign the outer installer executable last.
7. Verify signatures before any public release.
8. Use the hardened `Release Pipeline` dry-run path for rehearsals; do not use the deprecated `build-windows-test.yml` workflow or the legacy unsigned packaging shortcut.

Expected outcome:
- preflight passes
- signed ZIP is built from the signed bundle, not from unsigned build output
- signed installer payload is built from the signed bundle, not from unsigned build output
- signed installer verifies cleanly
- signed zip payload contains signed `svid.exe` / `vidcombo.exe` and shipped DLLs
- signing uses slot `9C` without touching the legacy ECC material in `9A`

## Phase 5: Windows Validation

Validate both brands on real Windows machines before publishing:

1. Fresh install on Windows 11 with Smart App Control ON
2. Fresh install on Windows 10
3. Upgrade install over an existing app version
4. In-app update from an older version to the new version
5. First launch after install
6. Download a test file after install/update

Pass criteria:
- no Smart App Control block dialog
- installer completes
- app launches from the installer `[Run]` step
- user data remains intact after upgrade

## Phase 6: Rollout Plan

1. Cut one patch release for `Svid` and one patch release for `VidCombo` with RSA signing only.
2. Validate download + installer from the public release URL.
3. Validate in-app update against the released Windows build.
4. Monitor support inbox, release analytics, and update-failure reports for 48-72 hours.
5. Only after the RSA release is stable, set repo/org variable `WINDOWS_SIGNING_PIV_SLOT=9c` so CI signs from slot `9C`.
6. Resume normal Windows release cadence.

## User Impact

- Existing installed users are not broken by this migration.
- The main benefit lands on:
  - Windows 11 users with Smart App Control ON
  - users who currently fail at installer launch
  - users whose in-app update downloads but cannot execute the installer
- This is a trust and release-engineering fix, not a data-model or installer-identity migration.

## Follow-Up Hardening

- Keep the new RSA policy enforced in CI.
- Add a permanent Windows 11 Smart App Control test lane to release QA.
- Evaluate moving Windows signing to Microsoft Artifact Signing after the RSA cutover is stable.
- Consider a dedicated backup signer token so one physical YubiKey is not a single point of release failure.

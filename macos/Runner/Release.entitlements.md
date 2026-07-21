# Release.entitlements rationale

The entitlements plist is intentionally minimal — Apple's
`AMFIUnserializeXML` codesign parser rejects multi-line `<!-- -->` comment
blocks even when they are valid W3C XML. Keep `Release.entitlements` as
a pure plist; document rationale here.

## Entitlements granted (and why)

### `com.apple.security.app-sandbox` — `false`

Required: the app spawns external binaries (yt-dlp, ffmpeg, gallery-dl)
downloaded at runtime. A sandbox profile that lets a non-codesigned
child process read/write arbitrary Downloads paths does not exist, so
we opt out of sandbox and rely on hardened runtime + notarization.

### `com.apple.security.cs.disable-library-validation` — `true`

The app bundles `native.framework` (signed by us) and loads Flutter
plugin dylibs that are signed during `--deep`, but the hardened runtime
treats some of them as third-party unless this is set. Removing this
flips notarized apps into a silent-dylib-load-failure state that is
painful to diagnose.

### `com.apple.security.network.client` — `true`
### `com.apple.security.files.downloads.read-write` — `true`
### `com.apple.security.files.user-selected.read-write` — `true`

The app downloads over HTTPS, writes to `~/Downloads` by default, and
lets the user pick an output folder.

## Entitlements removed (and why), as of 2026-04-24

### `com.apple.security.cs.allow-jit`

Flutter desktop release builds are AOT-compiled. There is no JIT at
runtime. This entitlement allows mapping writable+executable memory,
which is exactly the capability an exploit needs to land shellcode.

### `com.apple.security.cs.allow-unsigned-executable-memory`

Same reasoning as `allow-jit`. AOT binaries only execute pages that
were mapped from the signed `__TEXT` segment. Turning this off means
a memory-corruption bug cannot pivot through JIT-style W^X violation.

### `com.apple.security.network.server`

The app never binds a listening socket. It is a pure HTTPS client.

## Why this file lives next to the plist

`AMFIUnserializeXML` is stricter than libxml2 — long XML comments inside
the plist trigger `Failed to parse entitlements: AMFIUnserializeXML:
syntax error near line N` at codesign time. Big-tech convention is to
keep entitlement plists machine-minimal and document rationale in an
adjacent file. This file is that adjacent file.

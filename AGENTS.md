# Repository Guidelines

## Operating Contract
Snakeloader is production software. Before any non-trivial work, read `docs/ops/AI_OPERATING_CONTRACT.md` and start from `docs/ops/TASK_PACKET_TEMPLATE.md` unless the user explicitly asks for a quick one-off answer.

Codex's default role in this repo is reviewer/release gate, not autonomous releaser. Use the verdict protocol in `docs/ops/REVIEW_VERDICT_PROTOCOL.md`:

- `SIGN-OFF`: no release-blocking issue found.
- `SIGN-OFF WITH ASSUMPTIONS`: releaseable if the stated external authority/data is accepted.
- `BLOCK RELEASE`: only for P0/P1 with file/line or runtime proof, user impact, release consequence, and minimal fix path.
- `FOLLOW-UP`: P2/P3, uncertainty, cleanup, observability, or non-blocking caveat.

Do not convert "I cannot personally verify production data" into a blocker when another named authority/session supplied the data. Mark it as an assumption and continue reviewing the code consequences.

## Project Structure & Module Organization
`lib/` contains the Flutter desktop app. Organize app code by feature under `lib/features/<feature>/` and keep shared infrastructure in `lib/core/`; Rust bridge files live in `lib/bridge/`. `test/` mirrors the app structure and includes shared helpers in `test/helpers/` and `test/shared/`. `native/` is the Rust crate used by `flutter_rust_bridge`. `backend/` holds the Go API and the embedded React admin app in `backend/web/admin/`. `website/` is the static marketing site. Platform hosts live in `macos/`, `windows/`, `linux/`, and `android/`; bundled assets live in `assets/`.

## Build, Test, and Development Commands
Use Flutter `3.29.3` from `.fvmrc`.

- `./scripts/setup_dev.sh` installs Dart dependencies and regenerates Freezed, Riverpod, and Drift outputs after a clone or pull.
- `./scripts/dev.sh svid` or `./scripts/dev.sh vidcombo` switches branding, rebuilds the Rust library, and runs the macOS app.
- `fvm flutter analyze --no-pub` checks Dart/Flutter code against `flutter_lints`.
- `fvm flutter test` runs the app test suite.
- `cd native && cargo build` rebuilds the Rust crate directly.
- `cd backend && make run`, `make test`, `make build`, `make admin-dev` run the Go API, Go tests, production build, and Vite admin UI.
- `cd website && npm run build` builds the landing site.

## Coding Style & Naming Conventions
Follow standard Dart formatting: 2-space indentation, `snake_case.dart` filenames, `PascalCase` types, and `camelCase` members. Keep feature code layered by `data`, `domain`, and `presentation` where applicable. Prefer small Riverpod providers and focused services over large stateful widgets. Run `dart format lib test` before submitting. Do not hand-edit generated files such as `*.g.dart`, `*.freezed.dart`, or `lib/bridge/frb_generated*`; regenerate them instead.

## RCA And Production Discipline
Telemetry identifies where and how large a symptom is; it does not prove why. Call a root cause confirmed only after raw evidence, code-path proof, and repro or instrumentation agree. Payment/license impact requires proof that money moved or entitlement moved; pending counts alone are not revenue incidents.

## Release And Git Gates
Never push, tag, dispatch a release workflow, register a release, force-update users, or mutate production billing/license state without explicit user approval in the current thread. The local `origin` remote may not be the production remote; confirm remote and branch before any push. Treat `kynndev/main` as the production target only after checking current remotes and receiving approval.

## Testing Guidelines
App tests use `flutter_test` with `mocktail`; test files should end in `_test.dart` and mirror the source path, for example `lib/features/player/...` to `test/features/player/...`. Add or update tests for behavior changes in providers, services, widgets, and Rust-bridge-facing code. No explicit coverage gate is configured, so keep changed paths covered with targeted tests. Backend changes should also pass `cd backend && make test`.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commits with scopes, for example `feat(home): ...`, `fix(macos): ...`, and `ci(release): ...`. Keep commits focused and scope them by feature, platform, or subsystem. Pull requests should summarize user-visible impact, list verification steps, link related issues, and include screenshots or short recordings for UI, branding, or packaging changes. Call out regenerated code, signing/notarization changes, and release-script changes explicitly.

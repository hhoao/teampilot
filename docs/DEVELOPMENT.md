# Development guide

For contributors and maintainers. End-user overview: [README.md](../README.md). Architecture and AI conventions: [AGENTS.md](../AGENTS.md).

## Requirements

| Item | Notes |
|------|--------|
| [Flutter](https://docs.flutter.dev/get-started/install) | **stable** channel; SDK `^3.8.1` in `client`. After install/upgrade run `./tool/flutter_patches/apply_flutter_patches.sh` (see [Flutter SDK patches](flutter-patches.md)). |
| Git submodules | Required on first clone for vendored `client/packages/` |
| An agent CLI | At least one of `claude` / `codex` / `opencode` / `cursor` / `flashskyai` on **PATH** (or set in app settings) when exercising team terminals locally |
| Targets | **Linux / macOS / Windows / Android** (same as CI) |

### Linux 系统库(HTML 预览)

HTML 预览(webview)依赖 WebKitGTK 4.1:

```bash
sudo apt-get install libwebkit2gtk-4.1-0 libwebkit2gtk-4.1-dev libsoup-3.0-0 libsoup-3.0-dev
```

## First clone

```bash
git clone <repo-url>
cd teampilot
git submodule update --init --recursive
./tool/flutter_patches/apply_flutter_patches.sh   # required Flutter SDK patches
```

The apply script is idempotent (safe to re-run). CI applies the same step after
`flutter-action`. Convention: [Flutter SDK patches](flutter-patches.md).

## Local development

Work inside `client`:

```bash
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart   # first run / after clean: Noto Sans SC + Noto Color Emoji (~75MB, gitignored)
dart run tool/sync_material_icons.dart      # file type icons: regenerates lib/utils/ui/file_icon_mapping.g.dart and assets/file_icons/*.svg
dart run native_splash_screen_cli gen         # Linux/Windows native splash sources (gitignored; required before desktop build)
flutter run -d linux      # or macos, windows, android
# macOS: Info.plist sets FLTEnableImpeller=false (Impeller hover tear).
# `flutter run -d macos --no-enable-impeller` forces the same if the tool injects Impeller on.
```

Native splash pixel sources under `linux/runner/native_splash_screen_*.cc` and
`windows/runner/native_splash_screen_*.cpp` are generated and gitignored (~144MB).
Regenerate after changing `native_splash_screen.yaml` or on a fresh clone before a
desktop build. CI runs the same `gen` step.

- File type icons (VSCode Material Icon Theme): `dart run tool/sync_material_icons.dart`
  — regenerates `lib/utils/ui/file_icon_mapping.g.dart` and `assets/file_icons/*.svg`
  from the `material-icon-theme` npm package. Use `--npm-package <path>` to point
  at a pre-extracted package, `--force` to skip the version cache check.

Runtime font fetching is disabled; Simplified Chinese needs bundled fonts under `client/google_fonts/`.

After changing `json_serializable` models:

```bash
cd client
dart run build_runner build --delete-conflicting-outputs
```

### Static analysis

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Format and fix helpers (app sources only — `lib/`, `test/`, `tool/`; vendored `packages/` excluded, same as `analysis_options.yaml`):

```bash
cd client
bash scripts/fix_format.sh    # apply dart format + dart fix
bash scripts/check_format.sh  # verify format, pending fixes, and analyze (CI-aligned)
```

## Tests

Unit and widget tests (default; excludes the `integration` tag):

```bash
cd client
dart run tool/run_tests.dart
```

The project test entry point caps Flutter test concurrency at 4, which avoids
overloading the Flutter tester, PTY, and shell-process resources on machines
with many CPU cores. Pass a file, name, or other Flutter test options through
the same entry point; an explicit `-j` / `--concurrency` value is preserved.

Single file or by name:

```bash
dart run tool/run_tests.dart test/smoke/app_shell_smoke_test.dart
dart run tool/run_tests.dart --plain-name="test name"
```

The wrapper excludes the `integration` tag by default and caps concurrency at 4
for every invocation, including single-file and coverage runs. Pass
`--tags` or `--exclude-tags` explicitly when you need a different test
selection; integration tests should be selected deliberately.

### Never invoke `flutter test` directly

**Not even for a subset of tests.** Concurrent `flutter test` runs in the same
`client/` directory corrupt the shared incremental build cache
(`build/test_cache/…​.cache.dill.track.dill`) and hang for hours with
near-zero progress. Always go through the wrapper, which passes paths/options
straight to `flutter test`, caps concurrency, excludes integration tags, and
queues concurrent runs on a lock:

```bash
dart run tool/run_tests.dart test/pages/git_graph/ test/services/git/
```

Need real parallelism? Give each agent its own git worktree
(`git submodule update --init` + `flutter pub get` inside first).

### Test loop: fast inner, slow outer (do not invert it)

During development the inner loop is `flutter analyze` (seconds). Verify
behavior with **one test file**, narrowing with `--plain-name "…"` when useful:

```bash
dart run tool/run_tests.dart test/services/terminal/terminal_session_test.dart --plain-name "reclaim"
```

Run a module subset only at milestones. Run the full suite **only once, right
before claiming done**, and launch it in the background so you keep working
(docs, cleanup, commit prep) while it runs. Never kick off `test/services/`
(861 files) or the whole suite mid-development, and never while another agent
holds the lock — a queued full-suite run blocks every other agent's small
verification behind it.

#### Which changes need the full suite?

Pick the smallest check that still gives real confidence. The full suite
(`dart run tool/run_tests.dart` with no paths) is ~2k non-integration tests and
serializes every other agent behind the suite lock, so treat it as the
exception:

| Change | Verify with |
|--------|-------------|
| Any change | `flutter analyze --no-fatal-infos --no-fatal-warnings` (seconds) |
| Behavior inside one top-level directory / feature (`lib/services/<x>/`, `lib/pages/<x>/`, `lib/cubits/<x>/`, a single widget) | `dart run tool/run_tests.dart test/<mirrored dir>/` plus any test that directly imports the changed symbol |
| Docs, comments, formatting; i18n JSON only | analyze (run `dart run slang` first for i18n, then the affected page tests) |
| Shared base used across modules (`lib/models/`, `lib/utils/`, `lib/repositories/`, `lib/app/`, `lib/router/`, `lib/theme/`, `lib/main.dart`, shared `lib/services/` base such as storage/runtime context/logging/CLI registry/member placement) | full suite |
| Dependencies or build/generated inputs (`pubspec.yaml`/upgrade, `analysis_options.yaml`, `dart_test.yaml`, slang output, `*.g.dart`, build_runner) | full suite |
| A change spanning ≥2 top-level directories, or after a merge/rebase that pulled in others' work | full suite |
| Final delivery / opening a PR | full suite once (background); CI also runs it |

If you cannot tell whether a change is cross-cutting, run the module subset
first and save the full suite for the delivery checkpoint — do not default to
the whole suite on every edit.

**Observing shared runs (no lock needed).** Run records and logs live under
`client/.dart_tool/test_runs/` (gitignored, shared by every agent in the
checkout). `dart run tool/test_status.dart` lists recent runs (scope, status,
duration, HEAD, dirty); `--tail [id]` follows a running log; `--wait-for <id>`
waits for a run and returns its exit code. None of these take the suite lock,
so you can see that a full suite is already running and follow it instead of
queueing a duplicate:

- `dart run tool/run_tests.dart --reuse` skips a full run when a green full run
  already exists for the current **clean** HEAD with the same `pubspec.lock`
  (default freshness 30 min; `RUN_TESTS_REUSE_MAX_AGE_MINUTES` overrides).
  Dirty worktrees are never reused.
- `dart run tool/run_tests.dart --no-wait` exits `75` instead of blocking when
  another run holds the lock, after printing what is in progress.

### Profile-scoped SSH worker

Production SSH protocol ownership is exercised through the profile-worker
proxy. Use this focused worker/lifecycle loop while changing the worker, its
storage/member facades, or lifecycle wiring:

```bash
cd client
dart run tool/run_tests.dart \
  test/services/ssh/worker/ssh_profile_worker_manager_test.dart \
  test/services/ssh/worker/ssh_worker_storage_client_test.dart \
  test/services/ssh/worker/ssh_worker_member_session_test.dart \
  test/services/ssh/worker/ssh_worker_output_batcher_test.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/ssh_worker_forwarding_test.dart \
  test/services/ssh/ssh_profile_connection_coordinator_test.dart \
  test/services/terminal/terminal_transport_factory_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

The `SshClientFactory.connector`, injected reverse-tunnel factory, and
`SshMemberSession.testing` are deterministic direct-mode test adapters. They
are intentionally retained for unit tests; production construction does not
use them and must keep dartssh2 ownership in the profile worker.

Run real SSH coverage through the wrapper as well. The embedded shell test
keeps its existing library-availability guard, and the Docker tests keep their
existing Docker-availability guard:

```bash
cd client
dart run tool/run_tests.dart --tags integration \
  test/integration/embedded_pairing_test.dart \
  test/integration/embedded_shell_pty_integration_test.dart
dart run tool/run_tests.dart --tags integration \
  test/integration/remote_materialize_cache_docker_test.dart \
  test/integration/artifact_chunked_transfer_docker_test.dart
```

`teampilot_search` package (Rust engine + Dart wrapper):

```bash
cd client/packages/teampilot_search
cargo test --manifest-path rust/Cargo.toml && flutter test
```

Linux PTY integration tests (local) — filter by secondary tag (see table below):

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  dart run tool/run_tests.dart --tags "integration && linux-pty"
```

### Integration test tags

Declared in `client/dart_test.yaml`. Every integration test has the `integration` tag plus one or more secondary tags for CI filtering.

| Secondary tag | Tests | Needs |
|---------------|-------|--------|
| `cross-platform` | L1 bus ping/pong; embedded pairing loop | Loopback sockets only (the shell runs over pipes, no pty) |
| `linux-pty` | L2 CLI matrix + Claude mixed PTY; L3 also carries this tag; embedded bare-shell pty loop | `flutter build linux`, `libflutter_pty_new.so` on loader path, matching CLIs on PATH |
| `docker` | L3 mixed SSH worker; remote CLI install | Docker daemon (+ outbound network for install test) |

Examples:

```bash
cd client
dart run tool/run_tests.dart --tags "integration && cross-platform"   # L1 only
dart run tool/run_tests.dart --tags "integration && linux-pty"        # L2 + L3 (CI)
dart run tool/run_tests.dart --tags "integration && docker"           # L3 + remote CLI install
```

### Embedded connect server

Desktop **Connect** runs an embedded pure-Dart SSH server (`tp_sshd`) — no OS
OpenSSH server / Remote Login / `sshd` configuration is required on any
platform. Windows shows a one-time firewall prompt the first time a phone
pairs, because the server listens on a persisted high port; accepting it is
the only system interaction.

The full pairing loop (embedded server → QR offer → pairing POST over pinned
TLS → dartssh2 login → tp1 exec / host-info → SFTP → bare-shell channel →
revocation) is covered by `client/test/integration/embedded_pairing_test.dart`
(tagged `integration, cross-platform`). Its bare-shell stage runs the login
shell over plain pipes through the `PtySpawner` seam so the whole loop stays
cross-platform (flutter_pty needs the Flutter engine); the production
flutter_pty pseudo-terminal path — pty-req dimensions, window-change resize,
interactive echo, clean exit — is covered by
`client/test/integration/embedded_shell_pty_integration_test.dart`
(tagged `integration, linux-pty`, skipped unless `libflutter_pty_new` is on
the loader path). Real-device QR pairing remains in the Windows manual test
matrix, noted in the PR description. Run them with:

```bash
cd client
dart run tool/run_tests.dart --tags integration \
  test/integration/embedded_pairing_test.dart \
  test/integration/embedded_shell_pty_integration_test.dart
```

#### dartssh2 native crypto shim

The SSH packet ciphers `chacha20-poly1305@openssh.com` and AES-128/256-GCM run
on libcrypto through an FFI shim in the dartssh2 fork
(`client/packages/dartssh2/native/tp_sshd_crypto.c`) — a hard dependency with
no pure-Dart fallback for those three. Anything that exercises them — the
fork's own `dart test`, `tp_sshd`'s `dart test`, and the tp_sshd examples
(`demo_sshd`, `bench_cipher`) — needs the shim built once first:

```bash
cd client/packages/dartssh2 && ./native/build.sh
```

Requires a C compiler plus OpenSSL/LibreSSL **dev headers** (Debian/Ubuntu:
`apt install build-essential libssl-dev`; on macOS the headers ship with the OS
toolchain — LibreSSL covers every EVP API the shim uses).

The loader tries three things, in this order:

1. the bare library name (`libtp_sshd_crypto.so` / `.dylib` / `.dll`) through
   the OS loader — the packaged layout (Android jniLibs, iOS Frameworks, a
   desktop bundle's lib directory on the loader's search path);
2. `native/libtp_sshd_crypto.so`, the `build.sh` output, by walking up from the
   working directory or the script and via the package config of the package
   being run, so a stale local build always wins — rebuild it after pulling
   changes to the shim;
3. the shipped prebuilt at `native/prebuilt/<platform>/<arch>/`
   (`libtp_sshd_crypto.dylib` under `macos/universal/`, `tp_sshd_crypto.dll`
   under `windows/x64/`). That tree is produced by `native/ci-build-all.sh`,
   which builds and validates each lane (the C selftest where the host can
   execute the artifact, else size + format + exported-symbol checks; lane
   prerequisites in the script header). The artifacts are committed —
   `linux/x64` is in git today, the other lanes are CI outputs collected per
   `native/prebuilt/README.md`. The committed `linux/x64` artifact has
   `DT_NEEDED libcrypto.so.3`, so that lane needs **OpenSSL 3** at load time.

**Packaging is wired for the desktop targets and still missing for
android/ios.** The `tp_sshd_crypto_flutter` package
(`client/packages/tp_sshd_crypto_flutter/`) is a Flutter FFI plugin whose
platform lanes compile this shim into the app's library directory, so a
**linux / windows / macos** app build bundles `libtp_sshd_crypto.so` and the
loader's bare-name lookup finds it. Verify it on Linux with:

```bash
cd client && flutter build linux --release
ls build/linux/x64/release/bundle/lib/libtp_sshd_crypto.so
```

(To prove the *bundled* copy is what loads rather than a source-tree build,
move `client/packages/dartssh2/native/libtp_sshd_crypto.so` aside and run
anything that encrypts with `LD_LIBRARY_PATH=<bundle>/lib` from a directory
with no `native/` in reach — the package README has the exact smoke.)

**Android and iOS must not ship yet.** The Android lane needs a vendored
libcrypto first — the NDK ships neither OpenSSL headers nor a linkable
`libcrypto.so` (the plugin's README records the finding and what the lane
needs) — and this repository has no `ios/` directory at all. On those two
platforms a packaged build still fails on the first packet, so the fork's
gitlink must not reach an android/ios app release build until their lanes
land. macOS is wired but unverified here (no macOS toolchain on this host) —
treat its first CI/macOS build as the verification. `dart test` / `dart run` /
the examples are unaffected: they are unpackaged trees and resolve the local
build.

##### Acceptance measurements

Reference machine: x64 Linux, OpenSSL 3.5.5, Dart JIT, 2026-09-17. Both
figures are conditional on the negotiated cipher being one the shim
implements — `aes256-gcm`, `aes128-gcm` and `chacha20-poly1305@openssh.com`
are the first three entries of the default client cipher list (in that order),
and the SFTP run below negotiated `chacha20-poly1305`. `aes256-ctr` and
`aes128-ctr` are still PointyCastle and sit behind them in the same list as
fallbacks, so a server that forces one of those gets the old pure-Dart speed.
No pure-Dart AEAD path is left (`aes*-cbc` survives only as the private-key
file encryption mode).

Cipher path, isolated from sockets and SFTP:

```bash
cd client/packages/dartssh2 && ./native/build.sh
cd client/packages/tp_sshd && dart run example/bench_cipher.dart
```

`bench_cipher` warms up 100 packets per size and then times 3000 packets, so
the figure is steady-state. Runs recorded so far at 32 KiB packets, on hosts of
different load: **585.4 MB/s** (implementer, T5), **574 MB/s** (controller
re-run, T5), **913–1140 MB/s** (this branch head, idle host, 4 runs). The
spread is host load, not a different code path — the acceptance bar is
≥500 MB/s and every run clears it. The pre-swap pure-Dart baseline, same
machine, 2026-09-10: 40 MB/s at 4 KiB, 58 MB/s at 32 KiB; the FFI path at
4 KiB measured 180.1 MB/s (T5) and 281.7 MB/s (branch head).

End-to-end SFTP through the embedded server, real OpenSSH `sftp` client:

```bash
# terminal 1 — demo server (the banner prints the exact ssh/sftp commands)
cd client/packages/tp_sshd && dart run example/demo_sshd.dart --port 2222

# terminal 2 — 50 MB into the sandbox the banner names, then 9 downloads.
dd if=/dev/urandom of="$HOME/.tp_sshd_demo/sftp-root/big.bin" bs=1M count=50
for i in $(seq 1 9); do
  /usr/bin/time -f "%e s" sftp -P 2222 -b - \
    -i "$HOME/.tp_sshd_demo/device_key" \
    -o UserKnownHostsFile="$HOME/.tp_sshd_demo/known_hosts" \
    -o IdentitiesOnly=yes "$USER@127.0.0.1" <<< "get /big.bin /tmp/big.bin"
done
```

Cold is the **first** `get` after the server starts (fresh process: JIT warm-up
plus handshake); warm is the **median of the 8** that follow, each a fresh
`sftp` process and so a fresh connection. Measured on this branch head:
cold **0.84 s → ~60 MB/s**, warm **0.39–0.47 s, median 0.45 s → ~111 MB/s**.
T5 recorded 1.047 s → 47.8 MB/s cold and 0.51 s → ~98 MB/s warm on a busier
host, so the same procedure reproduces within host-load noise. The bar is ≥80
MB/s **warm**, which both sessions clear; cold does not, by design — the gap is
JIT warm-up, not protocol. Verify the transfer with `cmp` against the sandbox
file, and the negotiated cipher with `sftp -v` (expect
`chacha20-poly1305@openssh.com`).

### Mock model gateway + CLI message matrix

All mock model traffic for matrix / mixed-bus integration goes through
`tools/mock_model_gateway` (Anthropic Messages, OpenAI Chat, Codex Responses).
Package `dart test` covers L0 + L1 HTTP — no separate client L1 is required for
the gateway itself.

**L0 + L1 (gateway package, no vendor CLI):**

```bash
cd tools/mock_model_gateway && dart test
```

**L1 (client bus / cross-platform, no PTY):**

```bash
cd client && dart run tool/run_tests.dart --tags "integration && cross-platform"
```

**L2 (CLI message matrix — real CLI + ChatCubit + PTY + gateway, Linux):**

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  dart run tool/run_tests.dart --tags "integration && linux-pty" \
  test/integration/cli_message_matrix_*.dart
```

Also under `linux-pty`: legacy Claude mixed TeamBus L2
(`mixed_team_claude_bus_integration_test.dart`). L2 cells need the matching CLI
on PATH (`claude`, `flashskyai`, `codex`, `opencode`, …). TeamPilot pre-approves
third-party provider API keys in `.claude.json` (`customApiKeyResponses`) so
Claude Code skips the interactive "use this API key?" gate on first launch.

**Cursor L2:** blocked — public `cursor-agent` has no loopback model redirect
(auth is Cursor cloud only). Do not expect green Cursor matrix cells until a
public redirect exists; spike notes live on `CliTestProfile` for `CliTool.cursor`.

**Completion status (2026-08-04, `feat/matrix-roster-shape`):** see
[MATRIX.md](MATRIX.md) — cells are **CLI × Mode × RosterShape**; claude
native **replicated** green; `placementFiltered` deferred (unit only).

**L3 (local lead + Docker SSH worker, full ChatCubit + remote preflight):**

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  dart run tool/run_tests.dart test/integration/mixed_team_claude_docker_integration_test.dart --tags "integration && docker"
```

L3 uses `Dockerfile.mixed` (`teampilot-it-ssh-mixed:latest`) with Node + `claude` baked in. Most wall time is **cold start** (Docker + two Claude PTYs + remote preflight locate); once both members are idle, bus ping/pong should complete in **seconds** (`kickoffAndWaitForPingPong` allows 30s per attempt). Bare-image install coverage remains `remote_cli_install_docker_test.dart`.

Remote CLI install over Docker SSH (needs Docker daemon + outbound network):

```bash
cd client
dart run tool/run_tests.dart test/integration/remote_cli_install_docker_test.dart --tags "integration && docker"
```

Skips automatically when Docker is unavailable. First run builds `teampilot-it-ssh:latest` from `test/integration/docker/Dockerfile` (Debian + OpenSSH + socat, no Node/npm preinstalled).

### Test helpers (cubit / home storage)

When tests need the shared home plane (`testHomeStorage`) or a `RuntimeContext`:

```dart
import '../support/post_frame_test_harness.dart';

setUp(() => setUpTestAppStorage());
tearDown(() => tearDownTestAppStorage());
```

For post-frame async (`ChatCubit`), use `PostFrameTestHarness` and `runScheduledCallback` from the same file. Log noise like `RuntimeStorageContext.install() must be called` means fix the test harness, not ignore it.

### Coverage (optional)

Not required in CI; locally:

```bash
cd client
dart run tool/run_tests.dart --coverage
# with lcov: genhtml coverage/lcov.info -o coverage/html
```

## Code quality guidelines

Layering, soft file-size limits, Extension rules, and pre-release checklists: **[CODE_QUALITY.md](CODE_QUALITY.md)**. Read before editing large pages (`team_config_page`, `llm_config_workspace`) or `app_shell.dart`.

## Packaging & releases

CI uses the [fastforge](https://github.com/hhoao/fastforge) submodule at
`client/third_party/fastforge` (AppImage `StartupWMClass` support; upstream
[PR #360](https://github.com/fastforgedev/fastforge/pull/360)) to produce artifacts under `client/dist/`:

| Platform | Outputs |
|----------|---------|
| Linux | `.deb`, `.AppImage` |
| macOS | `.dmg` |
| Windows | `.msix`, `.exe` (Inno Setup), `.zip` |
| Android | `teampilot-<version>-armeabi-v7a.apk`, `…-arm64-v8a.apk` |

**Release (recommended):** Bump `version:` in `client/pubspec.yaml` to `X.Y.Z` before merging to `main`. [Auto Tag on Version Bump](../.github/workflows/auto-tag.yml) detects the change, pushes a **`vX.Y.Z`** tag, and dispatches [Release Packages](../.github/workflows/release.yml) via `workflow_dispatch` (tag pushes from `GITHUB_TOKEN` do not chain-trigger other workflows). That GitHub Release becomes **Latest**. Release notes come from [git-cliff](https://git-cliff.org/) using **Conventional Commits since the previous tag**.

**Preview:** Set `version:` to `X.Y.Z-preview.N` and merge to `main`. Auto Tag publishes `vX.Y.Z-preview.N` as a GitHub **prerelease** and leaves Latest unchanged. Or run Release Packages manually with **preview** enabled and `ref` empty or set to a branch or sha: the tag is `v{pubspec version}-preview.N`, using the next free N when pubspec is still a stable version. The packages still embed the pubspec version. A stable tag is never rewritten into a preview.

You can still run `git tag vX.Y.Z && git push origin vX.Y.Z` (a local push triggers `release.yml` via `on.push.tags`). `vX.Y.Z-preview.N` pushed the same way is a prerelease. **workflow_dispatch** without preview still builds any `ref` and publishes only when that ref is already a `v*` tag.

Changes under `client/` trigger [Client Build Verify](../.github/workflows/client-verify.yml):

- **Four platforms** (Linux, Windows, macOS, Android): `flutter analyze` and `dart run tool/run_tests.dart`.
- **Linux integration** (`integration-linux` job): L2 + L3 via `dart run tool/run_tests.dart --tags "integration && linux-pty"` after `flutter build linux --debug`, global `claude` CLI, and a cached `Dockerfile.mixed` image.

### Local packaging examples

```bash
git submodule update --init client/third_party/fastforge
bash tool/activate_fastforge.sh
# After upstream https://github.com/fastforgedev/fastforge/pull/360 is on pub.dev:
# dart pub global activate fastforge
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart
fastforge package --platform linux --targets deb,appimage
```

Windows `.exe` requires **Inno Setup 6** locally (same as CI):

```powershell
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart
fastforge package --platform windows --targets exe
```

Runnable binary without an installer:

```powershell
flutter build windows --release
# Output: client/build/windows/x64/runner/Release/TeamPilot.exe
```

OS-specific tooling matches the CI workflows. See [`client/linux/packaging/README.md`](../client/linux/packaging/README.md) for Linux details.

## Related documentation

| Doc | Topic |
|-----|--------|
| [AGENTS.md](../AGENTS.md) | AI guide: hard rules, doc index |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Core concepts, `services/chat/` layout, TeamBus, change conventions |
| [CODE_QUALITY.md](CODE_QUALITY.md) | File size, tests, Extension, tech-debt norms |
| [DEBUGGING.md](DEBUGGING.md) | Debugging process (search-first, root cause) |
| [CLAUDE.md](../CLAUDE.md) | Claude Code entry point (links to AGENTS.md) |
| [Linux packaging](../client/linux/packaging/README.md) | fastforge / deb / AppImage |

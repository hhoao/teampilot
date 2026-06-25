# Development guide

For contributors and maintainers. End-user overview: [README.md](../README.md). Architecture and AI conventions: [AGENTS.md](../AGENTS.md).

## Requirements

| Item | Notes |
|------|--------|
| [Flutter](https://docs.flutter.dev/get-started/install) | **stable** channel; SDK `^3.8.1` in `client` |
| Git submodules | Required on first clone for vendored `client/packages/` |
| An agent CLI | At least one of `claude` / `codex` / `opencode` / `cursor` / `flashskyai` on **PATH** (or set in app settings) when exercising team terminals locally |
| Targets | **Linux / macOS / Windows / Android** (same as CI) |

## First clone

```bash
git clone <repo-url>
cd teampilot
git submodule update --init --recursive
```

## Local development

Work inside `client`:

```bash
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart   # first run / after clean: Noto Sans SC (~50MB, gitignored)
dart run tool/sync_material_icons.dart      # file type icons: regenerates lib/utils/file_icon_mapping.g.dart and assets/file_icons/*.svg
flutter run -d linux      # or macos, windows, android
```

- File type icons (VSCode Material Icon Theme): `dart run tool/sync_material_icons.dart`
  — regenerates `lib/utils/file_icon_mapping.g.dart` and `assets/file_icons/*.svg`
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

## Tests

Unit and widget tests (default; excludes the `integration` tag):

```bash
cd client
flutter test --exclude-tags integration
```

Single file or by name:

```bash
flutter test test/widget_test.dart
flutter test --plain-name="test name"
```

Linux PTY integration tests (local):

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib flutter test --tags integration
```


### Mixed team Claude bus integration tests

**L0 (mock_anthropic package):**

```bash
cd tools/mock_anthropic && dart test
```

**L1 (fast, no claude):**

```bash
cd client && flutter test test/integration/mixed_team_bus_ping_pong_integration_test.dart --tags integration
```

**L2 (full ChatCubit + claude + PTY, Linux):**

```bash
cd client
flutter build linux --debug
TEAMPILOT_BUS_BRIDGE=/dev/null/teampilot-it-no-bridge \
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/mixed_team_claude_bus_integration_test.dart --tags integration
```

L2 requires `claude` on PATH. TeamPilot pre-approves third-party provider API keys in `.claude.json` (`customApiKeyResponses`) so Claude Code skips the interactive "use this API key?" gate on first launch.

**Debug mock API:**

```bash
dart run tools/mock_anthropic/bin/mock_anthropic.dart
```

Remote CLI install over Docker SSH (needs Docker daemon + outbound network):

```bash
cd client
flutter test test/integration/remote_cli_install_docker_test.dart --tags integration
```

Skips automatically when Docker is unavailable. First run builds `teampilot-it-ssh:latest` from `test/integration/docker/Dockerfile` (Debian + OpenSSH, no Node/npm preinstalled).

### Test helpers (cubit / AppStorage)

When tests touch `AppStorage` or `RuntimeStorageContext`:

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
flutter test --exclude-tags integration --coverage
# with lcov: genhtml coverage/lcov.info -o coverage/html
```

## Code quality guidelines

Layering, soft file-size limits, Extension rules, and pre-release checklists: **[CODE_QUALITY.md](CODE_QUALITY.md)**. Read before editing large pages (`team_config_page`, `llm_config_workspace`) or `app_shell.dart`.

## Packaging & releases

CI uses [fastforge](https://pub.dev/packages/fastforge) to produce artifacts under `client/dist/`:

| Platform | Outputs |
|----------|---------|
| Linux | `.deb`, `.AppImage` |
| macOS | `.dmg` |
| Windows | `.msix`, `.exe` (Inno Setup), `.zip` |
| Android | `teampilot-<version>-armeabi-v7a.apk`, `…-arm64-v8a.apk` |

**Release (recommended):** Bump `version:` in `client/pubspec.yaml` before merging to `main`. [Auto Tag on Version Bump](../.github/workflows/auto-tag.yml) detects the change, pushes a **`v*`** tag, and dispatches [Release Packages](../.github/workflows/release.yml) via `workflow_dispatch` (tag pushes from `GITHUB_TOKEN` do not chain-trigger other workflows). Release notes are still generated by [git-cliff](https://git-cliff.org/) from **Conventional Commits since the previous tag**—same as when you tag manually.

You can still run `git tag vX.Y.Z && git push origin vX.Y.Z` (a local push triggers `release.yml` via `on.push.tags`), or use **workflow_dispatch** on Release Packages with any `ref` (no GitHub Release unless that ref is already a tag).

Changes under `client/` trigger [Client Build Verify](../.github/workflows/client-verify.yml) on **Linux, Windows, macOS, and Android**: `flutter analyze` and `flutter test` (excluding the `integration` tag).

### Local packaging examples

```bash
dart pub global activate fastforge
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
| [AGENTS.md](../AGENTS.md) | AI guide: architecture, key paths, change conventions |
| [CODE_QUALITY.md](CODE_QUALITY.md) | File size, tests, Extension, tech-debt norms |
| [DEBUGGING.md](DEBUGGING.md) | Debugging process (search-first, root cause) |
| [TEAM_BUS_MEMBER_STATE.md](TEAM_BUS_MEMBER_STATE.md) | Mixed-team bus presence & member state |
| [CLAUDE.md](../CLAUDE.md) | Claude Code entry point (links to AGENTS.md) |
| [Linux packaging](../client/linux/packaging/README.md) | fastforge / deb / AppImage |

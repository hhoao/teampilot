# Development guide

For contributors and maintainers. End-user overview: [README.en.md](../README.en.md). Architecture and AI conventions: [CLAUDE.md](../CLAUDE.md). 简体中文：[DEVELOPMENT.md](DEVELOPMENT.md).

## Requirements

| Item | Notes |
|------|--------|
| [Flutter](https://docs.flutter.dev/get-started/install) | **stable** channel; SDK `^3.8.1` in `client` |
| Git submodules | Required on first clone for vendored `client/packages/` |
| `flashskyai` | On **PATH** or in app settings when exercising team terminals locally |
| `claude` | Optional; needed for Claude team / onboarding flows |
| Targets | **Linux / macOS / Windows / Android** (same as CI) |

## First clone

```bash
git clone <repo-url>
cd flashskyai-ui
git submodule update --init --recursive
```

## Local development

Work inside `client`:

```bash
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart   # first run / after clean: Noto Sans SC (~50MB, gitignored)
flutter run -d linux      # or macos, windows, android
```

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

## Packaging & releases

CI uses [fastforge](https://pub.dev/packages/fastforge) to produce artifacts under `client/dist/`:

| Platform | Outputs |
|----------|---------|
| Linux | `.deb`, `.AppImage` |
| macOS | `.dmg` |
| Windows | `.msix`, `.exe` (Inno Setup), `.zip` |
| Android | `teampilot-<version>-armeabi-v7a.apk`, `…-arm64-v8a.apk` |

Pushing a **`v*`** tag runs [Release Packages](../.github/workflows/release.yml) and publishes a **GitHub Release**. Use **workflow_dispatch** to build an arbitrary `ref`.

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
| [CLAUDE.md](../CLAUDE.md) | Repo layout, data dirs, architecture, conventions (contributors / AI) |
| [Plugin management design](superpowers/specs/2026-05-23-plugin-management-design.md) | Plugin architecture & storage |
| [RTK integration design](superpowers/specs/2026-05-24-rtk-integration-design.md) | Token compression hooks |
| [Linux packaging](../client/linux/packaging/README.md) | fastforge / deb / AppImage |

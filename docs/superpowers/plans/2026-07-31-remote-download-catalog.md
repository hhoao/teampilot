# Remote Download Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a URL-rewrite download catalog with shared resolver/downloader, wire App Update and Termux APK acquire through it, and expose device-local download-source settings.

**Architecture:** Features keep logical GitHub URLs. `RemoteDownloadResolver` expands them into ordered `DownloadCandidate`s from a catalog (v1: one enabled official GitHub identity source). Metadata GET/HEAD use `http.Client` against resolved candidates; **binary** fetches use `RemoteDownloader` (progress, optional sha256, failover). Termux setup gets a primary Download & install CTA via `AndroidPackageInstaller`. Catalog overrides persist under native app data (not Termux/SSH home). **Supersedes** Termux home setup UX that was links-only for installing Termux.

**Tech Stack:** Flutter/Dart, `package:http`, existing `github_http.dart` headers, `AndroidPackageInstaller`, device-local `Filesystem` JSON (same pattern as `TermuxConfigStore`), l10n ARB, `flutter_bloc` only where UI state needs it.

**Spec:** `docs/superpowers/specs/2026-07-31-remote-download-catalog-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/remote_download/download_candidate.dart` | `DownloadCandidate` (`uri`, `sourceId`) |
| `client/lib/services/remote_download/remote_download_source.dart` | `RemoteDownloadSource` model + JSON |
| `client/lib/services/remote_download/remote_download_catalog.dart` | Defaults + merge overrides; official GitHub identity source |
| `client/lib/services/remote_download/remote_download_resolver.dart` | Logical URI → candidates (origin rewrite / identity / passthrough) |
| `client/lib/services/remote_download/remote_download_http.dart` | Try GET/HEAD across candidates with feature-supplied headers (metadata path) |
| `client/lib/services/remote_download/remote_downloader.dart` | Binary fetch with progress, sha256, cancel, failover |
| `client/lib/services/remote_download/remote_download_settings_store.dart` | Device-local JSON under `{nativeAppData}/.remote-download/catalog.json` |
| `client/lib/cubits/remote_download_catalog_cubit.dart` | Load/save catalog; expose for settings + DI |
| `client/lib/services/termux/termux_apk_asset.dart` | Pure ABI → expected asset name / release helpers for `termux/termux-app` |
| `client/lib/services/termux/termux_apk_acquisition.dart` | Discover latest APK URL → Downloader → `AndroidPackageInstaller` |
| `client/lib/services/termux/termux_package_probe.dart` | Android MethodChannel probe for `com.termux` |
| `client/android/.../MainActivity.kt` | `isPackageInstalled` channel handler |
| `client/lib/pages/termux/termux_setup_page.dart` | Primary download CTA + progress; external links secondary |
| `client/lib/services/app/app_update_service.dart` | Resolve API/page/asset URLs; `downloadRelease` via Downloader |
| `client/lib/pages/config/download_sources_config_section.dart` | Settings UI: list sources, mirror base URL, restore defaults |
| `client/lib/cubits/config_cubit.dart` + `config_workspace.dart` + router | New `ConfigSection.downloadSources` |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | New strings |
| Tests under `client/test/services/remote_download/`, termux, app_update, pages |

**HTTP layering (locked for implementers):**

| Call | Path |
|------|------|
| Release metadata JSON (`api.github.com`) | Resolver → `RemoteDownloadHttp.get` (tries candidates) → parse JSON in feature |
| Tag redirect (`releases/latest`) / HEAD asset | Resolver → `RemoteDownloadHttp` GET(no follow) / HEAD |
| APK / release binary | Resolver → `RemoteDownloader.fetch` → `File` |

Do **not** force metadata through `RemoteDownloader` (it returns files).

**Mirror base URL semantics (settings advanced):** one optional override that adds/enables a source with `matchHost` in `{github.com, api.github.com}` and `rewriteOrigin = <user base>` (no trailing slash). Identity official source stays enabled at higher priority unless user disables it. Priority: official `10`, mirror `20` (lower number = tried first — document in code: sort ascending by `priority`).

**Termux release discovery:**

1. GET logical `https://api.github.com/repos/termux/termux-app/releases/latest` via Resolver + `RemoteDownloadHttp` + `githubApiHeaders`.
2. Pick asset whose `name` contains preferred ABI (`arm64-v8a` default; else `armeabi-v7a`) and ends with `.apk`; prefer names matching `termux-app_*_<abi>.apk` if multiple.
3. Use `browser_download_url` as logical download URL → `RemoteDownloader`.
4. If API fails: optional fallback construct `https://github.com/termux/termux-app/releases/latest` is **out of v1** unless cheap (YAGNI); surface retry + external GitHub link.

---

### Task 1: Models + default catalog

**Files:**
- Create: `client/lib/services/remote_download/download_candidate.dart`
- Create: `client/lib/services/remote_download/remote_download_source.dart`
- Create: `client/lib/services/remote_download/remote_download_catalog.dart`
- Create: `client/test/services/remote_download/remote_download_catalog_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';

void main() {
  test('defaultCatalog has one enabled official github identity', () {
    final catalog = RemoteDownloadCatalog.defaults();
    expect(catalog.sources, hasLength(1));
    final s = catalog.sources.single;
    expect(s.id, 'github-official');
    expect(s.enabled, isTrue);
    expect(s.rewriteOrigin, isNull);
    expect(s.matchHosts, containsAll(['github.com', 'api.github.com']));
  });

  test('mergeOverrides replaces by id and keeps defaults for missing', () {
    final merged = RemoteDownloadCatalog.defaults().mergeOverrides([
      RemoteDownloadSource(
        id: 'github-official',
        priority: 10,
        enabled: false,
        matchHosts: const ['github.com', 'api.github.com'],
      ),
    ]);
    expect(merged.sources.single.enabled, isFalse);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/services/remote_download/remote_download_catalog_test.dart`

- [ ] **Step 3: Minimal implementation**

```dart
// download_candidate.dart
class DownloadCandidate {
  const DownloadCandidate({required this.uri, required this.sourceId});
  final Uri uri;
  final String sourceId;
}

// remote_download_source.dart — fields: id, priority, enabled, matchHosts (List<String>),
// optional matchPathPrefix, optional rewriteOrigin; fromJson/toJson

// remote_download_catalog.dart
class RemoteDownloadCatalog {
  const RemoteDownloadCatalog(this.sources);
  final List<RemoteDownloadSource> sources;

  factory RemoteDownloadCatalog.defaults() => RemoteDownloadCatalog([
    RemoteDownloadSource(
      id: 'github-official',
      priority: 10,
      enabled: true,
      matchHosts: const ['github.com', 'api.github.com'],
      rewriteOrigin: null, // identity
    ),
  ]);

  RemoteDownloadCatalog mergeOverrides(List<RemoteDownloadSource> overrides) { /* by id */ }

  List<RemoteDownloadSource> enabledSorted() =>
      sources.where((s) => s.enabled).toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/remote_download/ client/test/services/remote_download/remote_download_catalog_test.dart
git commit -m "feat(remote-download): add catalog models and defaults"
```

---

### Task 2: Resolver

**Files:**
- Create: `client/lib/services/remote_download/remote_download_resolver.dart`
- Create: `client/test/services/remote_download/remote_download_resolver_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('identity source returns original uri', () {
  final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
  final uri = Uri.parse('https://api.github.com/repos/a/b/releases/latest');
  final c = resolver.resolve(uri);
  expect(c, hasLength(1));
  expect(c.single.uri, uri);
  expect(c.single.sourceId, 'github-official');
});

test('mirror rewrite keeps path and query', () {
  final catalog = RemoteDownloadCatalog([
    RemoteDownloadSource(
      id: 'github-official',
      priority: 10,
      enabled: true,
      matchHosts: const ['github.com'],
    ),
    RemoteDownloadSource(
      id: 'mirror',
      priority: 20,
      enabled: true,
      matchHosts: const ['github.com'],
      rewriteOrigin: 'https://mirror.example',
    ),
  ]);
  final resolver = RemoteDownloadResolver(catalog);
  final c = resolver.resolve(
    Uri.parse('https://github.com/o/r/releases/download/v1/a.apk?x=1'),
  );
  expect(c.map((e) => e.uri.toString()).toList(), [
    'https://github.com/o/r/releases/download/v1/a.apk?x=1',
    'https://mirror.example/o/r/releases/download/v1/a.apk?x=1',
  ]);
});

test('unmatched host returns single passthrough candidate', () {
  final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
  final uri = Uri.parse('https://example.com/file.bin');
  final c = resolver.resolve(uri);
  expect(c, hasLength(1));
  expect(c.single.sourceId, 'passthrough');
  expect(c.single.uri, uri);
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `RemoteDownloadResolver`**

- Accept either a fixed `RemoteDownloadCatalog` **or** `RemoteDownloadCatalog Function() catalogProvider` so callers can read the **live** catalog on every `resolve` (settings changes apply without restart). Prefer `catalogProvider` in production wiring (Task 10).
- Match `uri.host` against each enabled source’s `matchHosts` (case-insensitive).
- If `rewriteOrigin == null` → candidate uses original URI.
- Else parse `rewriteOrigin`, replace scheme/host/port; keep path + query.
- If no source matched → `[DownloadCandidate(uri: uri, sourceId: 'passthrough')]`.
- Optional `matchPathPrefix`: if set, also require `uri.path.startsWith(prefix)`.

- [ ] **Step 4: PASS + Commit**

```bash
git commit -m "feat(remote-download): resolve logical URLs to candidates"
```

---

### Task 3: RemoteDownloadHttp (metadata path)

**Files:**
- Create: `client/lib/services/remote_download/remote_download_http.dart`
- Create: `client/test/services/remote_download/remote_download_http_test.dart`

- [ ] **Step 1: Failing test with fake `http.Client`**

Use a small `_FakeClient` that fails first host and succeeds second (same pattern as `app_update_service_test.dart` fakes).

```dart
test('get tries next candidate after non-200', () async {
  // first candidate 500, second 200 with body 'ok'
  final httpLayer = RemoteDownloadHttp(
    client: fake,
    resolver: resolverWithMirror,
  );
  final res = await httpLayer.get(
    Uri.parse('https://api.github.com/repos/o/r/releases/latest'),
    headers: {'User-Agent': 'test'},
  );
  expect(res.statusCode, 200);
  expect(res.body, 'ok');
});
```

Also test `head` and `send` with `followRedirects: false` for latest-page fallback.

- [ ] **Step 2: FAIL → implement**

```dart
class RemoteDownloadHttp {
  RemoteDownloadHttp({required http.Client client, required RemoteDownloadResolver resolver});
  Future<http.Response> get(Uri logical, {Map<String, String>? headers});
  Future<http.Response> head(Uri logical, {Map<String, String>? headers});
  Future<http.StreamedResponse> send(
    http.BaseRequest Function(Uri candidateUri) buildRequest,
    Uri logical,
  );
}
```

On total failure throw `RemoteDownloadException` listing per-candidate status (for logs).

- [ ] **Step 3: PASS + Commit**

```bash
git commit -m "feat(remote-download): HTTP helper tries resolved candidates"
```

---

### Task 4: RemoteDownloader (binary path)

**Files:**
- Create: `client/lib/services/remote_download/remote_downloader.dart`
- Create: `client/test/services/remote_download/remote_downloader_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('fetch succeeds on second candidate', () async { ... });
test('sha256 mismatch skips candidate', () async { ... });
test('cancel stops mid-flight', () async { ... });
```

Use in-memory stream responses; write to `Directory.systemTemp`.

API sketch:

```dart
class RemoteDownloader {
  RemoteDownloader({required http.Client client, required RemoteDownloadResolver resolver});

  Future<File> fetch(
    Uri logical, {
    required String destFileName,
    Directory? tempRoot,
    Map<String, String>? headers,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  });
}
```

Behavior per spec §3: stream to temp, verify sha256 if set, atomic rename into temp dir return `File`. Prefer `crypto` package if already in pubspec; else add `crypto` only if missing.

- [ ] **Step 2: Implement + PASS + Commit**

```bash
git commit -m "feat(remote-download): binary downloader with failover and progress"
```

---

### Task 5: Settings store + cubit

**Files:**
- Create: `client/lib/services/remote_download/remote_download_settings_store.dart`
- Create: `client/lib/cubits/remote_download_catalog_cubit.dart`
- Create: `client/test/services/remote_download/remote_download_settings_store_test.dart`
- Create: `client/test/cubits/remote_download_catalog_cubit_test.dart`

- [ ] **Step 1: Store tests** (mirror `TermuxConfigStore` pattern)

Root = **native** app data path (`AppPathsBootstrapper.current.basePath` / injected `rootDir` + `LocalFilesystem`), file `.remote-download/catalog.json`:

```json
{
  "sources": [ { "id": "...", "priority": 20, "enabled": true, "matchHosts": ["github.com","api.github.com"], "rewriteOrigin": "https://mirror.example" } ],
  "mirrorBaseUrl": "https://mirror.example"
}
```

`loadEffectiveCatalog()` = `defaults().mergeOverrides(parsed sources)`; if `mirrorBaseUrl` set and no mirror source id `github-mirror`, synthesize one (priority 20, both hosts).

- [ ] **Step 2: Cubit** — `load()`, `setMirrorBaseUrl(String?)`, `restoreDefaults()`, `catalog` getter; emit after save.

Wire later in Task 10; for now unit-test with temp dir.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(remote-download): device-local catalog settings store"
```

---

### Task 6: Wire App Update through resolver / downloader

**Files:**
- Modify: `client/lib/services/app/app_update_service.dart`
- Modify: `client/test/services/app/app_update_service_test.dart`
- Modify constructors / call sites that construct `AppUpdateService` (grep `AppUpdateService(`)

- [ ] **Step 1: Extend constructor**

```dart
AppUpdateService({
  ...,
  RemoteDownloadResolver? resolver,
  RemoteDownloader? downloader,
  RemoteDownloadHttp? downloadHttp,
})
```

Defaults: identity-only catalog resolver + matching http/downloader on same `httpClient` when null (keeps tests green without mirrors).

- [ ] **Step 2: Route calls**

- `_fetchLatestReleaseFromApi`: `downloadHttp.get(Uri.parse(apiUrl), headers: await _apiHeaders())`
- `_resolveLatestReleaseTagName`: `downloadHttp.send` with `followRedirects: false` for the `releases/latest` page
- Any `releases.atom` (or other GitHub) GET used in the rate-limit fallback path: also via `downloadHttp` (grep the file for remaining `_httpClient.get/head/send` and route them)
- fallback HEAD: `downloadHttp.head(Uri.parse(downloadUrl), ...)`
- `downloadRelease`: `downloader.fetch(Uri.parse(release.downloadUrl), destFileName: release.assetName, headers: await _httpHeaders(), onProgress: ...)` — map progress double 0–1 from `(received, total)`

Preserve existing User-Agent / token headers on every attempt.

- [ ] **Step 3: Add one test** proving download hits second candidate when first fails (inject catalog with mirror + fake client).

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(app-update): route GitHub fetches through download catalog"
```

---

### Task 7: Termux APK asset helpers + acquisition

**Files:**
- Create: `client/lib/services/termux/termux_apk_asset.dart`
- Create: `client/lib/services/termux/termux_apk_acquisition.dart`
- Create: `client/test/services/termux/termux_apk_asset_test.dart`
- Create: `client/test/services/termux/termux_apk_acquisition_test.dart`

- [ ] **Step 1: Pure asset selection tests**

```dart
test('prefer arm64 asset from release JSON fixture', () {
  final url = selectTermuxApkDownloadUrl(
    assets: fixtureAssets,
    preferArm64: true,
  );
  expect(url, contains('arm64-v8a'));
});
```

Fixture: minimal list of `{name, browser_download_url, size}` maps shaped like GitHub API.

Logical API URL helper:

```dart
Uri termuxLatestReleaseApiUri() =>
  Uri.parse('https://api.github.com/repos/termux/termux-app/releases/latest');
```

ABI prefer: reuse `AppUpdateService.preferArm64AndroidApk()` or extract shared helper — prefer call existing static to avoid drift.

- [ ] **Step 2: `TermuxApkAcquisition`**

```dart
class TermuxApkAcquisition {
  TermuxApkAcquisition({
    required RemoteDownloadHttp http,
    required RemoteDownloader downloader,
    Future<int?> Function(String apkPath)? installApk, // default AndroidPackageInstaller.installApk
  });

  Future<TermuxApkAcquireResult> downloadAndInstall({
    bool? preferArm64,
    void Function(int received, int? total)? onProgress,
  });
}
```

Steps: GET latest → select asset → fetch → install → return status code / errors.

Unit-test with fakes; do not call real installer in tests.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(termux): APK discovery and acquisition via download catalog"
```

---

### Task 8: Package probe (Android)

**Files:**
- Modify: `client/android/app/src/main/kotlin/com/hhoa/teampilot/MainActivity.kt`
- Create: `client/lib/services/termux/termux_package_probe.dart`
- Create: `client/test/services/termux/termux_package_probe_test.dart` (mock channel)

- [ ] **Step 1: Kotlin**

In `MainActivity.configureFlutterEngine`:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hhoa.teampilot/packages")
  .setMethodCallHandler { call, result ->
    if (call.method == "isPackageInstalled") {
      val packageName = call.argument<String>("packageName") ?: ""
      try {
        packageManager.getPackageInfo(packageName, 0)
        result.success(true)
      } catch (_: Exception) {
        result.success(false)
      }
    } else result.notImplemented()
  }
```

- [ ] **Step 2: Dart**

```dart
class TermuxPackageProbe {
  static const channel = MethodChannel('com.hhoa.teampilot/packages');
  Future<bool> isTermuxInstalled() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await channel.invokeMethod<bool>('isPackageInstalled', {
        'packageName': 'com.termux',
      });
      return v ?? false;
    } catch (_) {
      return false; // conservative: show download CTA
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(termux): probe com.termux package installation"
```

---

### Task 9: TermuxSetupPage Download & install UX

**Files:**
- Modify: `client/lib/pages/termux/termux_setup_page.dart`
- Modify: `client/test/pages/termux/termux_setup_page_test.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`

**Supersedes** Termux home plan/spec links-only install step: primary CTA is in-app download.

- [ ] **Step 1: Add l10n keys**

- `termuxSetupDownloadInstall` — "Download & install Termux"
- `termuxSetupDownloading` — "Downloading Termux…"
- `termuxSetupInstalling` — "Installing…"
- `termuxSetupDownloadFailed` — "Could not download Termux. Retry or use a store link."
- `termuxSetupInstallDenied` — "Install was cancelled or blocked. Enable unknown apps if needed, then retry."
- `termuxSetupTermuxInstalled` — "Termux is installed"

Run codegen if the project uses `flutter gen-l10n` (usually automatic on `flutter test`).

- [ ] **Step 2: Page state**

On bootstrap: `TermuxPackageProbe().isTermuxInstalled()` → `_termuxInstalled`.

Re-probe when the app resumes (`AppLifecycleListener` / `WidgetsBindingObserver.didChangeAppLifecycleState` → `resumed`) so returning from the system installer updates the UI without requiring a full page reopen.

Install step UI:

- If installed: show success text / skip primary button.
- Else: primary `TpButton` key `termux_download_install_button`; show `LinearProgressIndicator` while downloading; secondary outline Play / F-Droid / GitHub unchanged.

Inject acquisition via constructor optional params for tests:

```dart
const TermuxSetupPage({
  this.packageProbe,
  this.apkAcquisition,
  ...
});
```

- [ ] **Step 3: Widget test** — missing package shows primary download button; tap triggers acquisition mock.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(termux): in-app Termux APK download and install CTA"
```

---

### Task 10: Settings UI + DI bootstrap

**Files:**
- Create: `client/lib/pages/config/download_sources_config_section.dart`
- Modify: `client/lib/cubits/config_cubit.dart` — add `ConfigSection.downloadSources` (+ `title` / `breadcrumb` / `routeSegment` switches)
- Modify: `client/lib/pages/config/config_workspace.dart` — dialog entry + hub tile + index map
- Modify: `client/lib/router/app_router.dart` (and any Android config hub / `android_shell_chrome.dart` section lists) so the new section routes
- Modify: app shell / bootstrap — provide `RemoteDownloadCatalogCubit` with store rooted at **native** `AppPaths` base path
- Wire resolver/http/downloader with `catalogProvider: () => cubit.state.catalog` (or equivalent) so mirror edits apply on the next request without restart
- Pass that live stack into `AppUpdateService` / Termux acquisition construction sites

- [ ] **Step 1: Settings section UI**

- List enabled sources (id, hosts, rewrite or “identity”).
- Text field: Mirror base URL (hint `https://mirror.example`).
- Buttons: Save, Restore defaults.
- Subtitle explaining mirrors apply to GitHub hosts for updates / Termux APK.

- [ ] **Step 2: l10n** for section title/subtitle/fields.

- [ ] **Step 3: Smoke test** settings section builds; cubit restoreDefaults clears mirror.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(settings): download sources catalog UI"
```

---

### Task 11: Verification

- [ ] **Step 1: Focused tests**

```bash
cd client && flutter test \
  test/services/remote_download/ \
  test/services/termux/termux_apk_asset_test.dart \
  test/services/termux/termux_apk_acquisition_test.dart \
  test/services/termux/termux_package_probe_test.dart \
  test/services/app/app_update_service_test.dart \
  test/pages/termux/termux_setup_page_test.dart \
  test/cubits/remote_download_catalog_cubit_test.dart
```

Expected: all PASS.

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Manual checklist (Android device/emulator)**

1. Settings → Download sources: defaults show official only; set a bogus mirror, confirm App Update / Termux still try official first.
2. Termux not installed: setup page shows Download & install; progress; system installer; after return, probe shows installed (or re-open page).
3. Termux installed: primary CTA hidden/disabled; Connect flow unchanged.
4. App Update still finds latest release and downloads APK/desktop asset.

- [ ] **Step 4: Final commit only if leftover doc/touch-ups**

---

## Out of scope (do not implement in this plan)

- Skill / Hub `codeload` / `raw.githubusercontent.com` consumers  
- npm / cargo mirrors  
- Bundling Termux APK in TeamPilot  
- Remote fleet catalog JSON  
- Changing Termux OpenSSH / Connect flow beyond install step UX  

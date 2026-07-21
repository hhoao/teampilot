# GitHub Device Flow Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Hub publish’s PAT-first auth with official OAuth App Device Flow, backed by an app-level GitHub credentials store shared by Settings and the publish wizard (PAT remains Advanced; env tokens remain for CI).

**Architecture:** Add `GithubDeviceFlowAuth` + `GithubCredentialsStore` + `GithubAccountCubit`; reuse one `GithubDeviceFlowPanel` in `/config/github` and the Hub publish auth step; map GitHub API 401 to `HubPublishErrorCode.unauthorized` so the wizard clears stored creds and returns to auth. Publish fork→PR path stays otherwise unchanged.

**Tech Stack:** Flutter, `flutter_bloc`, `http`, `url_launcher`, existing `SecureKeyValueStore`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-07-21-github-device-flow-auth-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/config/github_oauth_config.dart` | `GITHUB_OAUTH_CLIENT_ID` via `String.fromEnvironment` |
| `client/lib/services/github/github_device_flow_auth.dart` | Device code + poll protocol |
| `client/lib/services/github/github_credentials_store.dart` | Token/login/source + legacy migrate + env |
| `client/lib/cubits/github_account_cubit.dart` | Connection state machine |
| `client/lib/widgets/github/github_device_flow_panel.dart` | Shared connect / waiting / connected UI |
| `client/lib/pages/config/github_config_section.dart` | Settings body |
| `client/lib/cubits/config_cubit.dart` | `ConfigSection.github` |
| `client/lib/router/app_router.dart` | `/config/github` route |
| `client/lib/pages/config/config_workspace.dart` | Nav + section switch + settings dialog entry |
| `client/lib/pages/hub_publish/hub_publish_wizard_steps.dart` | Auth step uses panel + Advanced PAT |
| `client/lib/pages/hub_publish/hub_publish_wizard.dart` | Auth/Next/Switch account / 401 → auth |
| `client/lib/pages/hub_publish/show_hub_publish_wizard.dart` | Resolve shared store/cubit |
| `client/lib/services/hub_publish/github_registry_publisher.dart` | Add `unauthorized` error code |
| `client/lib/services/hub_publish/http_github_api_client.dart` | 401 → `unauthorized` |
| `client/lib/services/hub_publish/hub_publish_service.dart` | Depend on `GithubCredentialsStore` |
| Delete or thin-wrap: `hub_publish_credentials_store.dart` | Prefer delete after call-site migration |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | New GitHub / Device Flow strings |
| Tests under `client/test/services/github/`, `client/test/cubits/`, `client/test/pages/` | Protocol, store, cubit, wizard, settings |

---

### Task 1: OAuth client_id config

**Files:**
- Create: `client/lib/config/github_oauth_config.dart`
- Test: `client/test/config/github_oauth_config_test.dart` (optional if only `fromEnvironment` — prefer a tiny injectable helper used by Device Flow)

- [ ] **Step 1: Add config**

```dart
/// Official TeamPilot GitHub OAuth App client id for Device Flow.
///
/// Override: `--dart-define=GITHUB_OAUTH_CLIENT_ID=...`
/// Empty default disables Device Flow (Advanced PAT / env still work).
const String githubOauthClientId = String.fromEnvironment(
  'GITHUB_OAUTH_CLIENT_ID',
  defaultValue: '',
);

bool get githubDeviceFlowAvailable => githubOauthClientId.trim().isNotEmpty;
```

- [ ] **Step 2: Commit**

```bash
git add client/lib/config/github_oauth_config.dart
git commit -m "feat(github): add OAuth client_id dart-define config"
```

---

### Task 2: Device Flow protocol (TDD)

**Files:**
- Create: `client/lib/services/github/github_device_flow_auth.dart`
- Test: `client/test/services/github/github_device_flow_auth_test.dart`

- [ ] **Step 1: Write failing tests** covering:
  - `start` parses `user_code`, `device_code`, `verification_uri`, optional `verification_uri_complete`, `interval`, `expires_in`
  - `pollOnce` returns `pending` / `slowDown(newInterval)` / `denied` / `expired` / `success(token)`
  - `browserUri` prefers `verification_uri_complete` when non-empty

Use an injectable `Future<http.Response> Function(Uri, {Map? headers, Object? body})` or `http.Client` fake — match patterns in `http_github_api_client` tests if any; otherwise a simple callback interface on `GithubDeviceFlowAuth`.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/github/github_device_flow_auth_test.dart
```

- [ ] **Step 3: Implement `GithubDeviceFlowAuth`**

Endpoints (form-urlencoded):
- `POST https://github.com/login/device/code` — `client_id`, `scope=repo`
- `POST https://github.com/login/oauth/access_token` — `client_id`, `device_code`, `grant_type=urn:ietf:params:oauth:grant-type:device_code`
- Headers: `Accept: application/json`, plus existing `kGithubHttpUserAgent`

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/github/github_device_flow_auth.dart \
  client/test/services/github/github_device_flow_auth_test.dart
git commit -m "feat(github): implement Device Flow auth protocol"
```

---

### Task 3: `GithubCredentialsStore` (TDD) + replace hub publish store

**Files:**
- Create: `client/lib/services/github/github_credentials_store.dart`
- Test: `client/test/services/github/github_credentials_store_test.dart`
- Modify: all imports of `HubPublishCredentialsStore` → new store
- Delete: `client/lib/services/hub_publish/hub_publish_credentials_store.dart` (+ its test, migrate assertions)

Keys:
- New: `teampilot.github.v1.token`, `teampilot.github.v1.login`, `teampilot.github.v1.source` (`oauth`|`pat`)
- Legacy: `teampilot.hub_publish.v1.github_token` (read-once migrate into new keys, source `pat`)

API sketch:

```dart
enum GithubCredentialSource { oauth, pat }

class GithubCredentialsSnapshot {
  const GithubCredentialsSnapshot({
    required this.token,
    this.login,
    this.source,
  });
  final String token;
  final String? login;
  final GithubCredentialSource? source; // null when resolved from env only
}

class GithubCredentialsStore {
  Future<void> saveOAuth({required String token, required String login});
  Future<void> savePat(String token, {String? login});
  Future<void> clearStored(); // does not affect env
  Future<GithubCredentialsSnapshot?> readStored();
  Future<String?> resolveToken(); // stored → env
  Future<void> migrateLegacyHubPublishTokenIfNeeded();
}
```

- [ ] **Step 1: Failing tests** — round-trip oauth/pat; resolve prefers stored; env fallback; legacy key migrates once; `clearStored` leaves env resolvable

- [ ] **Step 2: Implement store + migrate call sites** (`HubPublishService`, `show_hub_publish_wizard.dart`, wizard, tests). Call `migrateLegacyHubPublishTokenIfNeeded()` from `resolveToken()` / `readStored()` (lazy once) **and** from `GithubAccountCubit.hydrate()` in Task 5 so existing PAT users are not stranded.

- [ ] **Step 3: Delete old store file after grepping no remaining references**

- [ ] **Step 4: Run**

```bash
cd client && flutter test test/services/github/github_credentials_store_test.dart \
  test/services/hub_publish/
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(github): add credentials store and replace hub publish token storage"
```

---

### Task 4: Map GitHub API 401 → `unauthorized`

**Files:**
- Modify: `client/lib/services/hub_publish/github_registry_publisher.dart` — add `HubPublishErrorCode.unauthorized`
- Modify: `client/lib/services/hub_publish/http_github_api_client.dart` — `_ensureOk` and other status checks: if `statusCode == 401` throw `unauthorized`
- Test: extend `client/test/services/hub_publish/github_registry_publisher_test.dart` or add `http_github_api_client` unit test with fake client

- [ ] **Step 1: Failing test** — fake 401 on `getRepo` (or `_ensureOk` path) yields `HubPublishErrorCode.unauthorized`

- [ ] **Step 2: Implement** — update `_ensureOk` **and** any bypass paths (notably `ensureFork`’s fork `POST` status check) so 401 maps to `unauthorized`

- [ ] **Step 3: Commit**

```bash
git commit -m "fix(hub-publish): map GitHub 401 to unauthorized error code"
```

---

### Task 5: `GithubAccountCubit` (TDD)

**Files:**
- Create: `client/lib/cubits/github_account_cubit.dart`
- Test: `client/test/cubits/github_account_cubit_test.dart`

State sketch:

```dart
enum GithubAccountStatus { unknown, disconnected, requesting, waiting, connected }

class GithubAccountState {
  final GithubAccountStatus status;
  final String? login;
  final GithubCredentialSource? source;
  final String? userCode;
  final String? verificationUri; // preferred browser URL
  final String? errorMessage;
  final bool deviceFlowAvailable;
}
```

Actions: `hydrate()`, `connect()`, `cancelConnect()`, `reopenBrowser()`, `disconnect()` / `switchAccount()`, `savePat(String)`, `onUnauthorized()`.

Inject: `GithubCredentialsStore`, `GithubDeviceFlowAuth`, `Future<void> Function(Uri) openUrl`, `Future<GithubUser> Function(String token) fetchUser` (or thin GitHub user fetcher), `Duration Function()` / sleep for poll interval (testable).

- [ ] **Step 1: Failing tests**
  - hydrate → connected when stored token exists
  - connect → waiting with userCode; poll success → saveOAuth + connected
  - access_denied / expired → disconnected + error
  - cancelConnect stops polling
  - savePat → connected source pat
  - switchAccount clears stored only
  - deviceFlowAvailable false → connect sets unavailable error / no-op

- [ ] **Step 2: Implement cubit**

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "feat(github): add GithubAccountCubit for Device Flow connection"
```

---

### Task 6: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Regenerate / sync `app_localizations*.dart`
- If ARB glyph warmup applies: `dart run tool/gen_warmup_glyphs.dart` per AGENTS.md

Add keys (names may be adjusted to match arb style):

| Key | EN (intent) |
|-----|-------------|
| `githubSettingsTitle` | GitHub |
| `githubSettingsSubtitle` | Connect GitHub to publish experts and teams to Hub |
| `githubSignIn` | Sign in with GitHub |
| `githubConnectedAs` | Connected as @{login} |
| `githubConnectedGeneric` | Connected to GitHub |
| `githubDisconnect` | Disconnect |
| `githubSwitchAccount` | Switch account |
| `githubWaitingCodeHint` | Enter this code on GitHub if prompted |
| `githubBrowserOpened` | Browser opened for authorization |
| `githubReopenBrowser` | Reopen browser |
| `githubDeviceFlowUnavailable` | GitHub sign-in is unavailable in this build. Use a personal access token. |
| `githubAuthExpired` | GitHub sign-in expired |
| `githubAuthDenied` | GitHub authorization cancelled |
| `githubAuthExpiredRetry` | Authorization expired. Try again. |
| `githubAdvancedPat` | Use a personal access token |
| `hubPublishAuthHint` | **Replace** with copy about browser auth + fork/PR (keep key) |
| `hubPublishConfirmHint` | Keep / lightly align with Device Flow wording |

- [ ] **Step 1: Edit ARB + gen-l10n**

```bash
cd client && flutter gen-l10n
```

- [ ] **Step 2: Commit**

```bash
git commit -m "l10n: add GitHub Device Flow and settings strings"
```

---

### Task 7: Shared `GithubDeviceFlowPanel`

**Files:**
- Create: `client/lib/widgets/github/github_device_flow_panel.dart`
- Test: `client/test/widgets/github/github_device_flow_panel_test.dart` (pump with mock cubit states)

- [ ] **Step 1: Build panel** driven by `GithubAccountCubit` / state props:
  - disconnected: purpose text + Sign in (disabled if `!deviceFlowAvailable` + unavailable hint)
  - waiting: user code (SelectableText), **copyable full verification URL** (required when `openUrl` fails; always fine to show), reopen, cancel
  - connected: `@login` or `githubConnectedGeneric` if login unknown, source label, disconnect (settings) or omit disconnect when `mode: publish` and show switch via parent
  - Optional `showAdvancedPat` ExpansionTile with token field + save

Use `TpButton` / existing form patterns from Hub publish / settings.

- [ ] **Step 2: Widget test** key states find expected keys (`github-sign-in`, `github-user-code`, …)

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(github): add shared Device Flow panel widget"
```

---

### Task 8: Settings `/config/github`

**Files:**
- Create: `client/lib/pages/config/github_config_section.dart`
- Modify: `client/lib/cubits/config_cubit.dart` — add `github` to enum + title/breadcrumb/routeSegment (`github`)
- Modify: `client/lib/router/app_router.dart` — route `/config/github`
- Modify: `client/lib/pages/config/config_workspace.dart` — nav row, hub entry, settings dialog entry, section body switch
- Wire `GithubAccountCubit` from ambient `BlocProvider` (**prefer finishing Task 9 first**, or temporarily `BlocProvider` a local cubit+store in this section until app wiring lands)
- Test: `client/test/pages/config/github_config_section_test.dart` (smoke)

- [ ] **Step 1: Add section + route + nav** (mirror `sshProfiles` wiring)

- [ ] **Step 2: Body = heading + `GithubDeviceFlowPanel(showAdvancedPat: true)`**

- [ ] **Step 3: Smoke test + commit**

```bash
git commit -m "feat(settings): add GitHub connection config section"
```

---

### Task 9: App wiring — shared store + cubit

**Files:**
- Modify: `client/lib/app/app_shell.dart` — construct one `GithubCredentialsStore` + `GithubAccountCubit`
- Modify: `client/lib/main.dart` — expose via `BlocProvider` / `RepositoryProvider` like other cubits (`sshProfileCubit` pattern); call `hydrate()` after create
- Modify: `client/lib/pages/hub_publish/show_hub_publish_wizard.dart` — prefer `context.read<GithubAccountCubit>()` / store from provider; keep optional overrides for tests

- [ ] **Step 1: Register providers** (shell construct + main tree)

- [ ] **Step 2: Update wizard entry to use shared instances**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(github): register shared GithubAccountCubit in app shell"
```

---

### Task 10: Hub publish wizard auth + 401 recovery

**Files:**
- Modify: `client/lib/pages/hub_publish/hub_publish_wizard_steps.dart` — replace `HubPublishAuthStep` body with panel + Advanced; update copy
- Modify: `client/lib/pages/hub_publish/hub_publish_wizard.dart`
  - Auth Next: require `resolveToken()` non-empty (from cubit/store), not only text field
  - Switch account: `cubit.switchAccount()`; stay on auth; do not auto `connect()`
  - On publish `HubPublishException` with `unauthorized`: `cubit.onUnauthorized()`, set step to `auth`, show `githubAuthExpired`
- Modify tests: `client/test/pages/hub_publish/hub_publish_wizard_test.dart`

- [ ] **Step 1: Update wizard tests first (fail)** — connected can next; unauthorized returns to auth; advanced PAT still saves

- [ ] **Step 2: Implement wizard changes** — put **Switch account** as a secondary dialog action on the auth step (alongside Next), calling `cubit.switchAccount()`; do not auto-start Device Flow

- [ ] **Step 3: Run**

```bash
cd client && flutter test test/pages/hub_publish/
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(hub-publish): Device Flow auth step and 401 re-auth"
```

---

### Task 11: Verification + release notes in plan handoff

- [ ] **Step 1: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/services/github/ test/cubits/github_account_cubit_test.dart \
  test/pages/hub_publish/ test/pages/config/github_config_section_test.dart \
  test/widgets/github/ --exclude-tags integration
```

- [ ] **Step 2: Manual checklist (not CI)**
  - Build with `--dart-define=GITHUB_OAUTH_CLIENT_ID=<dev app id>`
  - Settings → Sign in → browser → connected `@login`
  - Publish expert → skip paste → PR opens
  - Switch account → Advanced PAT still works
  - Build **without** client_id → Sign in disabled; PAT works

- [ ] **Step 3: Final commit** only if leftover cleanups; otherwise stop

**Release gate (human, outside code):** create GitHub OAuth App; ship production `client_id` in release pipeline defines.

---

## Execution notes

- Do **not** commit a real production `client_id` into the default `fromEnvironment` value until the OAuth App exists; empty default is intentional.
- Prefer TDD order inside each task; keep commits scoped.
- If `HubPublishCredentialsStore` deletion breaks many tests at once, do Task 3 as: add new store → dual-read adapter one commit → migrate callers → delete (still same task, extra commits OK).

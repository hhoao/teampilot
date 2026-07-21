# GitHub Device Flow auth for Hub publish

Replace the Hub publish wizard’s “paste a GitHub PAT” primary path with **GitHub OAuth Device Flow**, backed by an official TeamPilot OAuth App `client_id`. Credentials become an **app-level GitHub connection** (Settings + publish wizard share one store). PAT paste remains an advanced fallback; env tokens remain for CI/dev.

## Goal

Users who publish experts/teams to Hub should not need to know what a personal access token is or where to create one. They click **Sign in with GitHub**, approve in the browser, and continue.

## Non-goals (v1)

- Server-side token exchange / any TeamPilot backend
- Browser redirect OAuth or custom URL-scheme callbacks
- Calling GitHub’s token revoke API on disconnect (local clear only; copy may mention GitHub settings)
- Using GitHub login for features beyond Hub publish (store is reusable; only Settings + publish expose UI)
- Fine-grained GitHub App installation flow (classic OAuth App Device Flow + `repo` scope)

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| OAuth App | Official TeamPilot app; `client_id` shipped in the client |
| Primary auth | Device Flow |
| PAT paste | Collapsed **Advanced** fallback |
| Env `GITHUB_TOKEN` / `GH_TOKEN` | CI/dev fallback when nothing stored |
| Scope of UI | App-level connection in Settings **and** inline Device Flow in the publish wizard |
| Missing connection at publish | Run Device Flow **inside** the wizard, then continue |

## Architecture

```
Settings /config/github          Hub publish wizard auth step
        │                                    │
        └──────────┬─────────────────────────┘
                   ▼
           GithubAccountCubit
                   │
     ┌─────────────┴──────────────┐
     ▼                            ▼
GithubCredentialsStore    GithubDeviceFlowAuth
 (SecureKeyValueStore)     (client_id, HTTP)
     │
     ▼
HubPublishService.resolveToken()
     │
     ▼
GithubRegistryPublisher (unchanged fork → PR flow)
```

### `GithubDeviceFlowAuth`

- `start()` → `POST https://github.com/login/device/code` with `client_id` + `scope=repo`
- Returns `user_code`, `verification_uri`, `device_code`, `interval`, `expires_in`
- `poll(device_code)` until access token, denial, expiry, or cancel
- Handles `authorization_pending`, `slow_down`, `expired_token`, `access_denied`
- HTTP client injectable for tests

### `GithubCredentialsStore`

Replaces `HubPublishCredentialsStore` responsibilities:

| Field | Notes |
|-------|--------|
| `token` | Access token (OAuth or PAT) |
| `login` | GitHub username from `GET /user` when known |
| `source` | `oauth` \| `pat` \| (resolved-from-env is not persisted) |

Resolve order for publish: **stored token → env token**.

Migration: if the new key is empty, read the legacy hub-publish token key once and adopt it (source `pat` unless login is later refreshed).

### `GithubAccountCubit`

UI state machine: disconnected → requesting code → waiting (user_code + polling) → connected / error.

Actions: `connect()`, `cancelConnect()`, `disconnect()`, `savePat(token)`, `refreshProfile()`.

On successful OAuth or PAT save: persist token, fetch `/user` for `login`, emit connected.

### `client_id` configuration

- Production: official OAuth App `client_id` via `--dart-define=GITHUB_OAUTH_CLIENT_ID=…` or a release-controlled constant
- Missing/empty `client_id`: Device Flow entry disabled; Advanced PAT still works; user-facing copy explains GitHub sign-in is unavailable

## UI

### Settings — `/config/github`

Add a Config section (nav + hub entry alongside SSH profiles / about):

- **Disconnected:** short purpose (“Used to publish experts/teams to Hub”) + primary **Sign in with GitHub**
- **Waiting:** show `user_code` (copyable), status that the browser was opened, **Reopen browser**, **Cancel**
- **Connected:** `@login`, credential source (OAuth / PAT), **Disconnect**
- **Advanced (collapsed):** paste PAT → save as connected (`source=pat`)

### Hub publish wizard — auth step

| State | UI |
|-------|-----|
| Valid stored/env token | “Connected as @login” (or generic connected if login unknown) → **Next**; secondary **Switch account** |
| Not connected | Same Device Flow panel as Settings (inline) |
| Advanced | Collapsed “Use a personal access token” → existing paste field |

**Switch account:** clear **stored** credentials (not env), return to the disconnected auth panel, and **do not** auto-start Device Flow — user taps Sign in again (or uses Advanced PAT). Env-only tokens cannot be deleted from the app; saving a new OAuth/PAT token overrides them for resolve order.

Copy must explain: browser authorization; after approve, the app forks the Hub registry and opens a PR on the user’s behalf. Do not lead with “repo-scoped PAT required.”

### Device Flow interaction

1. User taps Sign in → request device code → **automatically** open the browser: prefer `verification_uri_complete` when GitHub returns it, else `verification_uri`
2. Show `user_code`; keep polling; offer **Reopen browser** (same URI preference)
3. If the browser fails to open: still show code + full verification URL (copyable); polling continues
4. Success → persist + profile → connected
5. Cancel / deny / expire → disconnected + clear error message

## Errors

| Case | User-facing | Behavior |
|------|-------------|----------|
| Browser won’t open | Code + URL still visible | Keep polling |
| `authorization_pending` | (none) | Continue |
| `slow_down` | (none) | Increase poll interval |
| `expired_token` | Authorization expired; try again | Stop; disconnected |
| `access_denied` | GitHub authorization cancelled | Stop; disconnected |
| Network / API failure | Short retryable message | Stay disconnected; can retry |
| Missing `client_id` | GitHub sign-in unavailable; use Advanced PAT | Disable Device Flow CTA |
| Publish gets 401 | GitHub sign-in expired | Clear **stored** creds (not env); wizard navigates back to the **auth** step |

401 handling is new relative to today’s generic `apiError` on confirm: detect unauthorized responses in the GitHub API client / `HubPublishException`, map to a dedicated signal the wizard understands, clear stored credentials, and send the user to auth (not only show an error on confirm).

Disconnect: delete local credentials only.

## Components / files (sketch)

| Unit | Role |
|------|------|
| `services/github/github_device_flow_auth.dart` | Device Flow protocol |
| `services/github/github_credentials_store.dart` | Secure token/login/source + legacy migrate + env |
| `cubits/github_account_cubit.dart` | Connection state |
| `pages/config/github_config_section.dart` (or similar) | Settings workspace |
| `widgets/github/github_device_flow_panel.dart` | Shared connect UI |
| Hub publish auth step | Embeds panel; Advanced PAT |
| `HubPublishService` | Uses new store’s `resolveToken()` |
| Router / `ConfigSection` | `/config/github` + nav |
| App wiring | Register cubit/store in `app_shell.dart`; share store/cubit from `show_hub_publish_wizard.dart`; add config nav in `config_workspace.dart` (and Android settings hub / chrome titles as needed) |

Prefer replacing call sites of `HubPublishCredentialsStore` over a long-lived compatibility wrapper.

## Testing

- Device Flow: fake HTTP — pending → success / denied / expired / slow_down
- Credentials store: resolve priority; legacy key migration
- Cubit: connect success writes login; disconnect clears; cancel mid-poll
- Wizard: connected can Next; disconnected starts waiting; Advanced PAT still works
- Settings: disconnected / connected / error widget tests
- No real GitHub or real production `client_id` in CI; inject test `client_id` + mocks

## Release gate

1. Create the TeamPilot GitHub OAuth App (Device Flow; redirect URL can be a docs URL)
2. Ship production `client_id` into release builds
3. Builds without `client_id` keep Advanced PAT + env path working
4. Docs/settings copy: connection purpose; publish still opens a PR pending maintainer merge

## Success criteria

- New user can connect GitHub and publish without creating a PAT manually (when `client_id` is present)
- Power users / CI can still use PAT or env token
- Settings shows connection status and allows disconnect
- Existing fork → Contents API → upstream PR publish path unchanged aside from token source

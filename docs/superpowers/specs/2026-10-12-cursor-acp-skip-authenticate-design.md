# Skip Cursor ACP `cursor_login` When Auth Files Exist

## Goal

Personal desktop Cursor ACP already has Official login files in the isolated
member home (same passthrough PTY uses). TeamPilot still always sends ACP
`authenticate { methodId: "cursor_login" }` after `initialize`. That RPC took
~28s on a logged-in machine and blocked the queued first prompt.

Skip `authenticate` when the isolated home's `auth.json` already has OAuth
tokens. Still send `cursor_login` when it does not.

Handshake progress UI and `session/new` latency are **out of scope**.

## Why skip is safe

Launch order on the failing session:

1. Cursor home passthrough (~14ms) — isolated `$HOME` already has
   `auth.json` (Linux: `$HOME/.config/cursor/auth.json` via `XDG_CONFIG_HOME`).
2. `initialize` (~0.4s).
3. Unconditional `authenticate` / `cursor_login` (~28s).
4. `session/new` (~16s, Cursor-owned; not this change).

PTY never calls `cursor_login`. It reads the same files. Cursor advertises
`authMethods: [cursor_login]` even when already logged in, so we cannot use
an empty `authMethods` list as the skip signal.

## Mechanism

CLI-agnostic wiring. No `if (cli == cursor)` in `services/acp/*` or
`productionAcpSpawner`.

`AcpCapability` keeps `authenticateMethodId` as the **declared** method
(`cursor_login` for Cursor, `null` for Gemini / Claude / Codex).

Add a default resolver used at spawn time, when `env` is already built:

```dart
Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
    authenticateMethodId;
```

`productionAcpSpawner` calls `resolveAuthenticateMethodId(env)` after
`initialize`. Null → skip `authenticate`. Non-null → existing
`raceHandshake(..., authenticating: true)` path.

`CursorAcpCapability` overrides the resolver:

1. Read `HOME` (fallback `USERPROFILE`) from `env`. Empty → do not skip
   (`cursor_login`).
2. Resolve the platform auth path with `CursorHomeLayout` using the same
   anchors Cursor launch already pins (`HOME` / `XDG_CONFIG_HOME` /
   `APPDATA` from `env` when present).
3. `Filesystem.readString` that path. Missing / unreadable / no tokens →
   `cursor_login`.
4. `CursorAuthArtifacts.authJsonIndicatesLoggedIn` true → return `null`.

Inject `Filesystem` (and optional platform) on `CursorAcpCapability` for
tests. Production default is `LocalFilesystem`. Capability may stay
`const CursorAcpCapability()` when both are omitted.

Passthrough has already run before spawn (`SessionConnectOrchestrator` then
`cursor-home-passthrough`). The resolver must not wait on passthrough.

## Failure policy

Unchanged when `cursor_login` is sent and fails: `AcpAuthenticateException`
→ not-logged-in copy. Do not try another argv candidate.

When authenticate is skipped and `session/new` later fails (expired token):
treat as today's generic ACP launch failure. **Do not** authenticate-and-retry
`session/new` in this change.

API-key Cursor (no Official `auth.json`) still authenticates.

## Tests

| Layer | Cases |
|-------|--------|
| `CursorAcpCapability` | Tokens in isolated `auth.json` + `HOME` env → resolver returns null. Missing file / empty tokens / empty HOME → `cursor_login`. Uses injected `Filesystem`. |
| `productionAcpSpawner` / capability plan | Gemini / Claude / Codex still skip authenticate (null id). Cursor declared id stays `cursor_login`. |
| Launch wiring | Existing authenticate-exit classification tests unchanged. |

No live `cursor-agent` in unit tests.

## Out of scope

- Handshake phase copy in the chat UI
- Speeding up or skipping `session/new`
- `session/load`
- Retry `authenticate` after a failed `session/new`
- Team / Android / SSH ACP
- Changing passthrough or isolated-home layout

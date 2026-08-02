# Provider credential host login design

**Date:** 2026-08-02  
**Status:** Approved for planning  
**Problem:** On Android (SSH home), official provider “Login” runs `Process.run` on the phone against a remote path such as `/root/.local/bin/cursor-agent`. That throws `ProcessException` → l10n `无法运行登录命令：{path}`. The same pattern exists for Claude / Codex / OpenCode login and logout. Credential **files** already go through `AppStorage.fs` (SFTP on SSH home); only the **CLI process** is on the wrong machine.

## Goal

1. Run official provider login/logout CLIs on the **current home** runtime plane (native / WSL / SSH), matching where credentials are stored.
2. For login, **stream** stdout/stderr, extract `https://` auth URLs, and open them on the **device** via an injected `openUrl` (mobile browser / desktop default handler).
3. One shared execution path for Claude, Cursor, Codex, and OpenCode — not four special cases.

## Non-goals

- Interactive embedded-terminal login UI (follow-up).
- Fixing unrelated one-shot CLIs (e.g. `cursor-agent models`) in this change.
- Parsing device-code / paste-back flows beyond opening the first useful HTTPS URL.
- Guaranteeing OAuth when the CLI only prints a **remote localhost** URL (document as limitation).

## Invariants

1. Credential file I/O stays on `AppStorage.fs` / provider service `Filesystem` (unchanged).
2. Credential CLI processes run on the same machine as `AppStorage.context` (via host starters), never bare device `Process.run` when home is WSL/SSH.
3. Login URL open happens on the **client device**, not via remote `xdg-open`.
4. Failure to extract/open a URL must not abort the login process; the CLI may still complete if the user authenticates another way.
5. Logout/revoke may use one-shot exec; login must use streaming so URLs are visible before exit.

## Design

### 1. Host streaming starter (symmetric with `HostOneShotRunner`)

Add under `client/lib/services/host/`:

| Type | Role |
|------|------|
| `ProcessRunHandle` (moved to `host/`) | `stdout` / `stderr` byte streams + `Future<int> exitCode` + `kill()` — keep this name |
| `HostProcessStarter` | `Future<ProcessRunHandle> start(HostRunRequest request)` |
| `LocalHostProcessStarter` | `Process.start` |
| `WslHostProcessStarter` | `wsl.exe` + `HostWslArgv` (same as one-shot) |
| `RemoteHostProcessStarter` | SSH non-PTY `execute` of `HostShellArgv.command(...)` |
| `hostProcessStarterForContext(RuntimeContext)` | Pick starter by `ctx.mode` |

**Reuse:** Move existing `ProcessRunHandle` / `SshProcessRunHandle` from `process_run_executor.dart` into `services/host/`. `ProcessRunExecutor` imports those types afterward — do not invent a second SSH streaming handle.

**SSH start wiring:** Extend `RemoteFileStore` (or a thin callback on the factory) with streaming `startShell(String command) → Future<HostProcessHandle>` using `SshClientFactory.clientForStorage` + `client.execute`, same as `WorkspaceRunPlatformFactory._sshSpawner`. Do **not** use `runOnStorage`’s short I/O timeout for login — OAuth can take many minutes; wait on session `done` / process exit only.

**Executable path:** Prefer the resolved preference path (remote/WSL Linux path). If a legacy `wsl.exe …` wrapper string appears while context is already WSL, unwrap with existing `CliInvocation` helpers so the starter does not double-wrap.

### 2. `ProviderCredentialHostRunner` (shared credential CLI façade)

New module under `client/lib/services/provider/` (e.g. `provider_credential_host_runner.dart`):

```dart
typedef CredentialOpenUrl = Future<void> Function(Uri uri);

class ProviderCredentialHostRunner {
  ProviderCredentialHostRunner({
    required HostOneShotRunner Function() oneShot,
    required HostProcessStarter Function() streaming,
    CredentialOpenUrl? openUrl,
    CredentialLoginUrlDetector urlDetector = const CredentialLoginUrlDetector(),
  });

  /// Logout / revoke: one-shot on home host.
  Future<HostRunResult> run(HostRunRequest request);

  /// Login: stream output, open first HTTPS URL(s) on device, return final result.
  Future<HostRunResult> runLogin(HostRunRequest request);
}
```

**`runLogin` behavior:**

1. `start(request)` on home streaming starter.
2. Decode stdout/stderr chunks (UTF-8 allowMalformed); append to full buffers for failure detail.
3. Maintain a **rolling tail buffer** across chunks so a URL split mid-stream is still detected (feed `previousTail + chunk` into the detector; keep only a bounded unsuffixed suffix, e.g. last 2 KiB).
4. `urlDetector.extract(...)` → if new `https` URI and `openUrl != null`, call `openUrl` once per distinct URI (dedupe).
5. Await exit code; return `HostRunResult(exitCode, stdout, stderr)`.
6. **Spawn / transport failures:** `ProviderCredentialHostRunner` normalizes them to `ProcessException` (or a single documented exception type the services already catch) so Claude/Cursor/Codex/OpenCode keep one `on ProcessException → loginProcessError` path. Do not leave raw SSH/`StateError` uncaught at the service layer.

**`CredentialLoginUrlDetector`:** pure function over text. Extract `https://` URLs (trim trailing punctuation). Prefer URLs whose host suggests auth/login/oauth/cursor/claude/openai when multiple appear; otherwise first https. Unit-test with sample CLI banners and split-chunk fixtures.

### 3. Wire all four credential services

Replace per-CLI `Process.run` defaults for **login and logout/revoke** with `ProviderCredentialHostRunner`:

| Service | Login argv (unchanged) | Also uses runner |
|---------|------------------------|------------------|
| `ClaudeProviderCredentialsService` | `auth login` / `auth logout` | yes |
| `CursorProviderCredentialsService` | `login` / `logout` | yes |
| `CodexProviderCredentialsService` | existing login/logout | yes |
| `OpencodeProviderCredentialsService` | existing login/logout | yes |

Each service keeps building env (`HOME` / provider isolation) and executable resolution. Change only the process launch:

- Build `HostRunRequest(executable, arguments, environment: …)`.
- Login → `runner.runLogin`; logout → `runner.run`.
- Map `HostRunResult` into existing `loginCommandResult` / failure helpers (extend helpers to accept `HostRunResult` or a tiny shared result typedef — drop hard dependency on `dart:io` `ProcessResult` where practical).

Constructor injection:

- `ProviderCredentialHostRunner? hostRunner` (tests inject fakes).
- Production default: runner built from `() => hostOneShotRunnerForContext(AppStorage.context)` + `() => hostProcessStarterForContext(AppStorage.context)` + optional `openUrl`.

Bootstrap (`app_shell` / `CliBootstrap`): pass the same shared runner (or factory) into all four credential services and register them on `CliToolRegistry` as today. `openUrl` = `launchUrl(..., LaunchMode.externalApplication)` (same as GitHub device flow).

Capabilities (`*ProviderCredentialCapability`) stay unchanged — they already call `runAuthLogin` / revoke.

### 4. Error handling & UX

| Case | Behavior |
|------|----------|
| Spawn fails (missing binary on host, SSH down) | Existing `loginProcessError(executable)` — detail remains the executable path |
| Non-zero exit | Existing `loginFailed` with stderr detail |
| Exit 0 but probe not ready | Existing `verifyFailed` (+ Cursor clears partial artifacts) |
| URL open throws / returns false | Log via `AppLogger`; continue waiting for CLI |
| No URL in output | Continue; user may still complete auth if CLI uses another channel |

No new primary UI for this slice. Optional follow-up: surface captured URL as selectable text if open fails.

### 5. Testing

| Layer | Tests |
|-------|-------|
| `CredentialLoginUrlDetector` | Pure unit tests: punctuation, multiple URLs, preference order |
| `ProviderCredentialHostRunner.runLogin` | Fake `HostProcessStarter` emitting chunks then exit; assert `openUrl` called once per URI; assert result aggregates stdout |
| `ProviderCredentialHostRunner.run` | Fake one-shot returns exit/stderr |
| Per-CLI credentials services | Keep existing tests; swap `processRunner` → host runner fake (or adapter) so login still writes auth files via in-memory `Filesystem` |
| Host starters | Extend `host_one_shot_runner_test` style coverage for streaming local starter; SSH/WSL via fakes |

## Data flow

```
UI Login button
  → AppProviderCubit.runProviderCredentialAction(login)
  → *ProviderCredentialCapability.execute
  → *ProviderCredentialsService.runAuthLogin
       → ensure provider home on AppStorage.fs
       → ProviderCredentialHostRunner.runLogin(HostRunRequest)
            → hostProcessStarterForContext(AppStorage.context).start
            → stream → URL detector → openUrl(device)
            → exit → HostRunResult
       → probe auth artifacts on fs
  → refresh credential status in UI
```

## File map (expected)

| Path | Action |
|------|--------|
| `client/lib/services/host/process_run_handle.dart` (or equivalent) | Move/create — shared `ProcessRunHandle` |
| `client/lib/services/host/host_process_starter.dart` | Create — Local/WSL/Remote + `forContext` |
| `client/lib/services/host/host_one_shot_runner*.dart` | Unchanged API; streaming is additive |
| `client/lib/services/storage/remote_file_store.dart` | Add streaming shell start |
| `client/lib/services/run/process_run_executor.dart` | Import shared handle from host |
| `client/lib/services/provider/provider_credential_host_runner.dart` | Create |
| `client/lib/services/provider/credential_login_url_detector.dart` | Create |
| `client/lib/services/provider/credential_process_result.dart` | Accept `HostRunResult` |
| `client/lib/services/provider/{claude,cursor,codex,opencode}/*_credentials_service.dart` | Use host runner |
| `client/lib/app/app_shell.dart` | Wire runner + `openUrl` |
| `client/test/services/host/*` / `provider/*` | New + updated tests |

## Success criteria

1. On Android SSH home, Cursor (and other official) Login no longer fails with `loginProcessError` solely because the path is remote.
2. When the CLI prints an `https://` login URL to stdout/stderr, the device opens it (best-effort).
3. Desktop native/WSL login/logout still work; unit tests cover runner + URL detector + at least one CLI service path.
4. No per-CLI copy of SSH/WSL spawn logic outside `services/host/`.

## Follow-ups (out of scope)

- Embedded terminal login for TUIs that need a PTY.
- Apply the same host runner to `CursorAgentModelsService` and other preference-path one-shots.
- Selectable “open login URL” chip when `openUrl` fails.

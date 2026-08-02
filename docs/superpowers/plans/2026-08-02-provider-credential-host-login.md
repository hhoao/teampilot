# Provider Credential Host Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run official provider login/logout CLIs on the home runtime plane (native/WSL/SSH), stream login stdout to open HTTPS auth URLs on the device, and stop Android SSH home from failing with `loginProcessError` on remote paths like `/root/.local/bin/cursor-agent`.

**Architecture:** Move shared `ProcessRunHandle` into `services/host/`, add `HostProcessStarter` (symmetric with `HostOneShotRunner`), then introduce `ProviderCredentialHostRunner` (one-shot logout + streaming login + URL open). Wire Claude/Cursor/Codex/OpenCode credential services and bootstrap `openUrl` via `launchUrl`.

**Tech Stack:** Flutter/Dart, existing `HostOneShotRunner` / `HostRunRequest` / `HostRunResult`, dartssh2 `SSHSession`, `url_launcher`.

**Spec:** `docs/superpowers/specs/2026-08-02-provider-credential-host-login-design.md`

**Skills:** @superpowers/test-driven-development @superpowers/verification-before-completion

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/provider/credential_login_url_detector.dart` | Pure HTTPS URL extract + auth-host preference |
| `client/test/services/provider/credential_login_url_detector_test.dart` | Detector unit tests |
| `client/lib/services/host/process_run_handle.dart` | Moved `ProcessRunHandle` + `SshProcessRunHandle` + local `_ProcessRunHandle` |
| `client/lib/services/run/process_run_executor.dart` | Import handle from host; drop local handle classes |
| `client/lib/services/host/host_process_starter.dart` | `HostProcessStarter` + Local/WSL/Remote impls |
| `client/lib/services/host/host_process_starter_for_context.dart` | `hostProcessStarterForContext` |
| `client/lib/services/storage/remote_file_store.dart` | `startShell(command)` → streaming `ProcessRunHandle` |
| `client/test/services/host/host_process_starter_test.dart` | Local/WSL starter fakes |
| `client/lib/services/provider/provider_credential_host_runner.dart` | Shared login/logout façade |
| `client/test/services/provider/provider_credential_host_runner_test.dart` | Runner + URL open + exception normalize |
| `client/lib/services/provider/credential_process_result.dart` | Accept `HostRunResult` (or dual overload) |
| `client/lib/services/provider/cursor/cursor_provider_credentials_service.dart` | Use host runner |
| `client/lib/services/provider/claude/claude_provider_credentials_service.dart` | Use host runner |
| `client/lib/services/provider/codex/codex_provider_credentials_service.dart` | Use host runner |
| `client/lib/services/provider/opencode/opencode_provider_credentials_service.dart` | Use host runner |
| `client/lib/app/app_shell.dart` | Shared runner + `openUrl` into credential services |
| Existing credential service tests | Adapt to host-runner fakes |

---

### Task 1: `CredentialLoginUrlDetector`

**Files:**
- Create: `client/lib/services/provider/credential_login_url_detector.dart`
- Create: `client/test/services/provider/credential_login_url_detector_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/credential_login_url_detector.dart';

void main() {
  const detector = CredentialLoginUrlDetector();

  test('extracts https URL and strips trailing punctuation', () {
    final uris = detector.extractAll(
      'Visit https://authenticator.cursor.sh/login?code=abc).',
    );
    expect(uris.single.toString(), 'https://authenticator.cursor.sh/login?code=abc');
  });

  test('prefers auth-like host when multiple https URLs present', () {
    final uris = detector.extractAll(
      'Docs https://example.com/docs then https://claude.ai/oauth/authorize?x=1',
    );
    expect(uris.first.host, 'claude.ai');
  });

  test('returns empty when no https URL', () {
    expect(detector.extractAll('no link http://insecure.example'), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider/credential_login_url_detector_test.dart`

Expected: FAIL (library not found)

- [ ] **Step 3: Write minimal implementation**

```dart
/// Extracts https login URLs from CLI stdout/stderr text.
class CredentialLoginUrlDetector {
  const CredentialLoginUrlDetector();

  static final RegExp _httpsUrl = RegExp(
    r'https://[^\s<>\"\']+',
    caseSensitive: false,
  );

  static const _preferredHostHints = [
    'cursor',
    'claude',
    'anthropic',
    'openai',
    'oauth',
    'login',
    'auth',
  ];

  /// All distinct https URIs, preferred hosts first.
  List<Uri> extractAll(String text) {
    final found = <Uri>[];
    final seen = <String>{};
    for (final match in _httpsUrl.allMatches(text)) {
      var raw = match.group(0)!;
      raw = raw.replaceFirst(RegExp(r'[)\],.;:]+$'), '');
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme.toLowerCase() != 'https') continue;
      final key = uri.toString();
      if (!seen.add(key)) continue;
      found.add(uri);
    }
    found.sort((a, b) {
      final ap = _isPreferred(a) ? 0 : 1;
      final bp = _isPreferred(b) ? 0 : 1;
      return ap.compareTo(bp);
    });
    return found;
  }

  Uri? extractFirst(String text) {
    final all = extractAll(text);
    return all.isEmpty ? null : all.first;
  }

  bool _isPreferred(Uri uri) {
    final host = uri.host.toLowerCase();
    return _preferredHostHints.any(host.contains);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/provider/credential_login_url_detector_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/provider/credential_login_url_detector.dart \
  client/test/services/provider/credential_login_url_detector_test.dart
git commit -m "$(cat <<'EOF'
feat(provider): add credential login URL detector

EOF
)"
```

---

### Task 2: Move `ProcessRunHandle` to `services/host/`

**Files:**
- Create: `client/lib/services/host/process_run_handle.dart`
- Modify: `client/lib/services/run/process_run_executor.dart`
- Modify any imports that referenced handle types only from executor (grep `ProcessRunHandle` / `SshProcessRunHandle`)

- [ ] **Step 1: Create host module with types moved from executor**

Move into `process_run_handle.dart`:

- `abstract class ProcessRunHandle`
- `class SshProcessRunHandle`
- Local concrete handle used by `Process.start` (name it `LocalProcessRunHandle`, public, so starters can reuse)

Keep `ProcessRunOutput`, `ProcessSpawner`, `SshProcessSpawner`, `ProcessRunExecutor` in executor file; import handle from host.

- [ ] **Step 2: Update imports and run existing run/host tests**

Run: `cd client && flutter test test/services/run/ test/services/host/host_one_shot_runner_test.dart`

Expected: PASS (no behavior change)

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/host/process_run_handle.dart \
  client/lib/services/run/process_run_executor.dart
# plus any import-only call sites
git commit -m "$(cat <<'EOF'
refactor(host): move ProcessRunHandle into services/host

EOF
)"
```

---

### Task 3: `HostProcessStarter` + context factory + `RemoteFileStore.startShell`

**Files:**
- Create: `client/lib/services/host/host_process_starter.dart`
- Create: `client/lib/services/host/host_process_starter_for_context.dart`
- Modify: `client/lib/services/storage/remote_file_store.dart`
- Create: `client/test/services/host/host_process_starter_test.dart`

- [ ] **Step 1: Write failing tests for Local + WSL starters**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/host/host_process_starter.dart';
import 'package:teampilot/services/host/process_run_handle.dart';

class _FakeHandle implements ProcessRunHandle {
  _FakeHandle({required this.exit, this.stdoutChunks = const []});
  final int exit;
  final List<String> stdoutChunks;
  @override
  Future<int> get exitCode async => exit;
  @override
  Stream<List<int>> get stdout async* {
    for (final c in stdoutChunks) {
      yield utf8.encode(c);
    }
  }
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  void kill() {}
}

void main() {
  test('WslHostProcessStarter prefixes wsl.exe argv', () async {
    late String exe;
    late List<String> args;
    final starter = WslHostProcessStarter(
      distro: 'Ubuntu',
      spawner: ({
        required executable,
        required arguments,
        workingDirectory,
        environment,
        includeParentEnvironment = true,
      }) async {
        exe = executable;
        args = arguments;
        return _FakeHandle(exit: 0);
      },
    );
    await starter.start(
      const HostRunRequest(
        executable: '/usr/bin/cursor-agent',
        arguments: ['login'],
        environment: {'HOME': '/home/u'},
      ),
    );
    expect(exe, 'wsl.exe');
    expect(args, contains('/usr/bin/cursor-agent'));
    expect(args, contains('login'));
  });
}
```

(Adjust spawner typedef to match implementation.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/host/host_process_starter_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement starters**

`host_process_starter.dart`:

```dart
abstract interface class HostProcessStarter {
  Future<ProcessRunHandle> start(HostRunRequest request);
}

class LocalHostProcessStarter implements HostProcessStarter {
  // Process.start → LocalProcessRunHandle
  // Injectable spawner for tests
}

class WslHostProcessStarter implements HostProcessStarter {
  // HostWslArgv.processInvocation → Process.start wsl.exe
}

class RemoteHostProcessStarter implements HostProcessStarter {
  RemoteHostProcessStarter({
    required Future<ProcessRunHandle> Function(String command) startShell,
  });
  // HostShellArgv.command(...) then startShell
}
```

`host_process_starter_for_context.dart`:

```dart
HostProcessStarter hostProcessStarterForContext(RuntimeContext ctx) {
  return switch (ctx.mode) {
    StorageBackendMode.ssh => RemoteHostProcessStarter(
      startShell: ctx.remoteFileStore!.startShell,
    ),
    StorageBackendMode.wsl => WslHostProcessStarter(
      distro: ctx.target.wslDistro,
    ),
    StorageBackendMode.native => LocalHostProcessStarter(),
  };
}
```

`RemoteFileStore.startShell`:

```dart
Future<ProcessRunHandle> startShell(String command) async {
  final client = await _clientFactory.clientForStorage(_profile);
  final session = await client.execute(command);
  return SshProcessRunHandle(session);
}
```

**Important:** Do not wrap this path in `SshStorageIo.awaitOrThrow` with the short storage I/O timeout — login waits on session completion only.

- [ ] **Step 4: Run starter tests**

Run: `cd client && flutter test test/services/host/host_process_starter_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/host/host_process_starter.dart \
  client/lib/services/host/host_process_starter_for_context.dart \
  client/lib/services/storage/remote_file_store.dart \
  client/test/services/host/host_process_starter_test.dart
git commit -m "$(cat <<'EOF'
feat(host): add HostProcessStarter for streaming CLI on home plane

EOF
)"
```

---

### Task 4: `ProviderCredentialHostRunner`

**Files:**
- Create: `client/lib/services/provider/provider_credential_host_runner.dart`
- Create: `client/test/services/provider/provider_credential_host_runner_test.dart`
- Modify: `client/lib/services/provider/credential_process_result.dart`

- [ ] **Step 1: Write failing runner tests**

Cover:

1. `run` delegates to one-shot and returns `HostRunResult`.
2. `runLogin` concatenates streamed stdout **and stderr**, opens first preferred URL once, dedupes.
3. Split-chunk URL: emit `https://auth.` then `example.com/x` across two chunks → still opens.
4. URL printed only on **stderr** is still opened.
5. `openUrl` throw does not fail the run (exit 0 still success result).
6. Non-`ProcessException` from `start` is rethrown as `ProcessException`.
7. Static `ProviderCredentialHostRunner.forAppStorage({CredentialOpenUrl? openUrl})` binds lazy `hostOneShotRunnerForContext(AppStorage.context)` + `hostProcessStarterForContext(AppStorage.context)` (for service defaults / Task 5 fallback).

```dart
test('runLogin opens URL across chunk boundary', () async {
  final opened = <Uri>[];
  final runner = ProviderCredentialHostRunner(
    oneShot: () => _FailOneShot(),
    streaming: () => _ScriptedStarter([
      utf8.encode('Open https://auth.'),
      utf8.encode('cursor.sh/login\n'),
    ], exitCode: 0),
    openUrl: (uri) async => opened.add(uri),
  );
  final result = await runner.runLogin(
    const HostRunRequest(executable: 'cursor-agent', arguments: ['login']),
  );
  expect(result.exitCode, 0);
  expect(opened.single.host, 'auth.cursor.sh');
});
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/services/provider/provider_credential_host_runner_test.dart`

- [ ] **Step 3: Implement runner**

Behavior per spec:

- Listen to **both** stdout and stderr; each chunk updates the same rolling tail (≤ 2 KiB) and full buffers.
- Rolling tail ≤ 2 KiB for URL scan (`tail + chunk`).
- Dedupe opened URIs.
- On `openUrl` error: `AppLogger` (or silent in tests); continue.
- Catch any spawn/start error → `throw ProcessException(executable, arguments, error.toString())`.
- Provide `forAppStorage({CredentialOpenUrl? openUrl})` factory as production/service default.

- [ ] **Step 4: Update `loginCommandResult` to accept `HostRunResult`**

Prefer:

```dart
Future<CredentialActionResult> loginCommandResult({
  required HostRunResult result,
  ...
})
```

Update call sites as services migrate (Task 5–6). Temporary overload accepting both `ProcessResult` and `HostRunResult` is OK for one PR if needed:

```dart
Future<CredentialActionResult> loginCommandResult({
  int? exitCode,
  Object? stderr,
  // or
  HostRunResult? hostResult,
  ProcessResult? processResult,
})
```

Cleanest: switch helpers to `HostRunResult` only and map in services.

- [ ] **Step 5: Tests PASS + commit**

```bash
git add client/lib/services/provider/provider_credential_host_runner.dart \
  client/test/services/provider/provider_credential_host_runner_test.dart \
  client/lib/services/provider/credential_process_result.dart
git commit -m "$(cat <<'EOF'
feat(provider): add ProviderCredentialHostRunner with streaming login URLs

EOF
)"
```

---

### Task 5: Wire Cursor credentials service (primary bug)

**Files:**
- Modify: `client/lib/services/provider/cursor/cursor_provider_credentials_service.dart`
- Modify: `client/test/services/provider/cursor/cursor_provider_credentials_service_test.dart`

- [ ] **Step 1: Update tests to inject `ProviderCredentialHostRunner` fake**

Replace `processRunner:` mocks with a host runner whose `runLogin`/`run` invoke the same auth-file write side effects and return `HostRunResult`.

Keep assertions on `login` argv / `HOME` env — move env checks into how the service builds `HostRunRequest` (spy on runner requests if useful).

- [ ] **Step 2: Run cursor credential tests — expect FAIL**

Run: `cd client && flutter test test/services/provider/cursor/cursor_provider_credentials_service_test.dart`

- [ ] **Step 3: Implement service wiring**

Constructor:

```dart
CursorProviderCredentialsService({
  ...
  ProviderCredentialHostRunner? hostRunner,
  // Keep processRunner only if still needed for tests during migration; prefer remove.
})
```

Replace `_runCursor` body:

```dart
Future<HostRunResult> _runCursor(
  List<String> subcommand, {
  required String providerId,
  required bool login,
  Map<String, String> platformEnv = const {},
}) async {
  final executable = _resolvedCursorExecutable();
  final env = {
    ...platformEnv,
    ...loginEnvironment(providerId, useWslPaths: _usePosixCliPaths()),
  };
  // Prefer raw preference path + subcommand; do NOT CliInvocation.resolveProcessLaunch
  // when host starter already selects WSL/SSH (avoids double-wrap).
  final request = HostRunRequest(
    executable: _hostExecutable(executable),
    arguments: _hostArguments(executable, subcommand),
    environment: env,
  );
  final runner = _hostRunner ?? ProviderCredentialHostRunner.forAppStorage();
  return login ? runner.runLogin(request) : runner.run(request);
}
```

Helpers `_hostExecutable` / `_hostArguments`: if `CliInvocation.fromExecutable` says `usesWsl` and home starter is WSL, unwrap to Linux path + rest args; otherwise use path + subcommand.

`_usePosixCliPaths`: true when `AppStorage` is installed and context mode is wsl/ssh; else fall back to `CliInvocation.usesWsl` for native Windows WSL-wrapper strings.

`runAuthLogin` / `revokeCredentials`: use `_runCursor(..., login: true/false)` + `loginCommandResult(result: hostResult, ...)`.

- [ ] **Step 4: Tests PASS**

Run: `cd client && flutter test test/services/provider/cursor/cursor_provider_credentials_service_test.dart`

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(cursor): run provider login on home HostProcessStarter

EOF
)"
```

---

### Task 6: Wire Claude, Codex, OpenCode the same way

**Files:**
- Modify: `claude_provider_credentials_service.dart` + test
- Modify: `codex_provider_credentials_service.dart` + test (if present)
- Modify: `opencode_provider_credentials_service.dart` + test (if present)

- [ ] **Step 1: Mirror Task 5 for each service**

Same injection pattern; keep each CLI’s subcommand lists unchanged (`auth login`, `login`, `providers login -p …`).

- [ ] **Step 2: Run affected tests**

```bash
cd client && flutter test \
  test/services/provider/claude/claude_provider_credentials_service_test.dart \
  test/services/provider/cursor/cursor_provider_credentials_service_test.dart \
  test/services/provider/codex/ \
  test/services/provider/opencode/
```

Expected: PASS (skip missing suites)

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(provider): run Claude/Codex/OpenCode credential CLI on home host

EOF
)"
```

---

### Task 7: Bootstrap shared runner + `openUrl` in `app_shell`

**Files:**
- Modify: `client/lib/app/app_shell.dart` (credential service construction ~671–694)
- Optionally: small factory helper on `ProviderCredentialHostRunner`

- [ ] **Step 1: Build one runner and pass into all four services**

```dart
Future<void> openCredentialLoginUrl(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

final credentialHostRunner = ProviderCredentialHostRunner(
  oneShot: () => hostOneShotRunnerForContext(AppStorage.context),
  streaming: () => hostProcessStarterForContext(AppStorage.context),
  openUrl: openCredentialLoginUrl,
);

// Claude/Cursor/Codex/OpenCode ... hostRunner: credentialHostRunner
```

Ensure `CliBootstrap` / registry configure still receives these instances.

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new errors in touched files

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(app): wire credential host runner and device openUrl

EOF
)"
```

---

### Task 8: Verification

- [ ] **Step 1: Run focused regression suite**

```bash
cd client && flutter test \
  test/services/provider/credential_login_url_detector_test.dart \
  test/services/provider/provider_credential_host_runner_test.dart \
  test/services/host/host_process_starter_test.dart \
  test/services/host/host_one_shot_runner_test.dart \
  test/services/provider/cursor/cursor_provider_credentials_service_test.dart \
  test/services/provider/claude/claude_provider_credentials_service_test.dart \
  test/services/provider/codex/ \
  test/services/provider/opencode/ \
  test/services/run/
```

Expected: all PASS

- [ ] **Step 2: Manual checklist (Android SSH home)**

1. Open Cursor official provider → Login
2. Confirm no `无法运行登录命令：/root/.local/bin/cursor-agent`
3. If CLI prints HTTPS URL, device browser opens
4. After successful remote auth, probe shows authenticated

- [ ] **Step 3: Final commit only if leftover fixups remain**

---

## Notes for implementers

- **Do not** use `RemoteFileStore.runHost` / `runOnStorage` for login — short timeout + no streaming.
- **Do not** call remote `xdg-open`; always device `openUrl`.
- Prefer one shared runner instance at bootstrap over four independently defaulting to `AppStorage.context` (still OK as fallback for tests).
- YAGNI: no PTY login UI, no models-service migration in this plan.

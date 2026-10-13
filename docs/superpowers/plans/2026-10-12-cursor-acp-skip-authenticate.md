# Skip Cursor ACP `cursor_login` When Auth Files Exist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skip ACP `authenticate` / `cursor_login` when the isolated Cursor home already has OAuth tokens in `auth.json`, so logged-in personal desktop sessions do not wait ~28s before `session/new`.

**Architecture:** Keep `authenticateMethodId` as the declared method. Add `AcpCapability.resolveAuthenticateMethodId(env)` (default: return the getter). `CursorAcpCapability` overrides it by reading isolated-home `auth.json` via injected `Filesystem`. `productionAcpSpawner` uses the resolver after `initialize`. No `if (cli == cursor)` in ACP mechanics.

**Tech Stack:** Flutter/Dart (`teampilot`), existing `CursorHomeLayout` / `CursorAuthArtifacts`, injectable `Filesystem`.

**Spec:** `docs/superpowers/specs/2026-10-12-cursor-acp-skip-authenticate-design.md`

## Global Constraints

- No `if (cli == cursor)` in `services/acp/*` or `productionAcpSpawner`. Skip logic lives on `CursorAcpCapability`.
- Do not change `session/new`, handshake UI copy, passthrough, or retry-authenticate-after-failed-new.
- Failure when `cursor_login` is actually sent stays `AcpAuthenticateException` → not-logged-in. Do not try another argv candidate.
- Declared `authenticateMethodId` stays `'cursor_login'` for Cursor and `null` for Gemini / Claude / Codex.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- l10n unchanged. Diagnostics → `AppLogger` only if a log is necessary; do not add `print`.
- Inner loop: `flutter analyze --no-fatal-infos --no-fatal-warnings` then one test file. Full suite only before claiming done.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/registry/capabilities/acp_capability.dart` | Default `resolveAuthenticateMethodId` |
| `client/lib/services/cli/cursor/capabilities/acp.dart` | Cursor override: read isolated `auth.json` |
| `client/lib/cubits/session/acp/acp_launch_wiring.dart` | Spawner calls the resolver with `env` |
| `client/test/services/cli/cursor/cursor_acp_capability_test.dart` | Tokens / missing / empty HOME cases |
| `client/test/services/cli/gemini/gemini_acp_capability_test.dart` | Default resolver still null |
| `client/test/cubits/session/acp/acp_launch_wiring_test.dart` | Helper uses resolver, not the getter |

---

### Task 1: Resolve authenticate from isolated `auth.json`

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/acp_capability.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/acp.dart`
- Modify: `client/test/services/cli/cursor/cursor_acp_capability_test.dart`
- Modify: `client/test/services/cli/gemini/gemini_acp_capability_test.dart`

**Interfaces:**
- Consumes: `CursorHomeLayout.authJson`, `CursorAuthArtifacts.authJsonIndicatesLoggedIn`, `Filesystem.readString`
- Produces: `Future<String?> AcpCapability.resolveAuthenticateMethodId(Map<String, String> env)` — default returns `authenticateMethodId`. Cursor returns `null` when tokens exist, else `'cursor_login'`.

- [ ] **Step 1: Write the failing tests**

Append to `cursor_acp_capability_test.dart` (keep existing tests). Pin `CursorHomePlatform.linux` so the suite is host-independent (`auth.json` is `$HOME/.config/cursor/auth.json`):

```dart
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/cursor/provider/cursor_auth_artifacts.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../../support/in_memory_filesystem.dart';

const _loggedInAuth = '{"accessToken":"at1","refreshToken":"rt1"}';
const _loggedOutAuth = '{"accessToken":"","refreshToken":""}';

CursorAcpCapability _linuxCap(Filesystem fs) => CursorAcpCapability(
  fs: fs,
  platform: CursorHomePlatform.linux,
);

String _linuxAuthPath(String home) =>
    CursorHomeLayout(platform: CursorHomePlatform.linux).authJson(home);

test('resolveAuthenticateMethodId skips cursor_login when auth.json has tokens',
    () async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  const home = '/iso/home';
  await fs.writeString(_linuxAuthPath(home), _loggedInAuth);
  final cap = _linuxCap(fs);
  expect(cap.authenticateMethodId, 'cursor_login');
  expect(
    await cap.resolveAuthenticateMethodId({'HOME': home}),
    isNull,
  );
});

test('resolveAuthenticateMethodId sends cursor_login when auth.json is missing',
    () async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  final cap = _linuxCap(fs);
  expect(
    await cap.resolveAuthenticateMethodId({'HOME': '/iso/home'}),
    'cursor_login',
  );
});

test('resolveAuthenticateMethodId sends cursor_login when tokens are empty',
    () async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  const home = '/iso/home';
  await fs.writeString(_linuxAuthPath(home), _loggedOutAuth);
  final cap = _linuxCap(fs);
  expect(
    await cap.resolveAuthenticateMethodId({'HOME': home}),
    'cursor_login',
  );
});

test('resolveAuthenticateMethodId sends cursor_login when HOME is empty',
    () async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  final cap = _linuxCap(fs);
  expect(await cap.resolveAuthenticateMethodId(const {}), 'cursor_login');
  expect(
    await cap.resolveAuthenticateMethodId({'HOME': '  '}),
    'cursor_login',
  );
});

test('resolveAuthenticateMethodId falls back to USERPROFILE when HOME is absent',
    () async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  const home = '/iso/home';
  await fs.writeString(_linuxAuthPath(home), _loggedInAuth);
  final cap = _linuxCap(fs);
  expect(
    await cap.resolveAuthenticateMethodId({'USERPROFILE': home}),
    isNull,
  );
});
```

Append to `gemini_acp_capability_test.dart` in the existing `authenticateMethodId is null` test (or a sibling):

```dart
test('resolveAuthenticateMethodId defaults to authenticateMethodId', () async {
  const cap = GeminiAcpCapability();
  expect(await cap.resolveAuthenticateMethodId({'HOME': '/x'}), isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_acp_capability_test.dart --plain-name="resolveAuthenticateMethodId"`

Expected: FAIL — `resolveAuthenticateMethodId` / named `fs` / `platform` args do not exist on `CursorAcpCapability`.

- [ ] **Step 3: Add the default resolver and Cursor override**

In `acp_capability.dart`, after `authenticateMethodId`:

```dart
  /// Spawn-time authenticate method. Default: [authenticateMethodId].
  ///
  /// Cursor returns null when isolated-home `auth.json` already has tokens.
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
      authenticateMethodId;
```

In `cursor/capabilities/acp.dart`:

```dart
import '../../../io/filesystem.dart';
import '../../../io/local_filesystem.dart';
import '../provider/cursor_auth_artifacts.dart';
import '../provider/cursor_home_layout.dart';

final class CursorAcpCapability implements AcpCapability {
  const CursorAcpCapability({this.fs, this.platform});

  final Filesystem? fs;
  final CursorHomePlatform? platform;

  @override
  String? get authenticateMethodId => 'cursor_login';

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async {
    final home = (env['HOME'] ?? env['USERPROFILE'] ?? '').trim();
    if (home.isEmpty) return authenticateMethodId;
    final filesystem = fs ?? LocalFilesystem();
    final layout = CursorHomeLayout(
      pathContext: filesystem.pathContext,
      platform: platform,
    );
    final content = await filesystem.readString(layout.authJson(home));
    if (content != null &&
        CursorAuthArtifacts.authJsonIndicatesLoggedIn(content)) {
      return null;
    }
    return authenticateMethodId;
  }
  // existing methods unchanged
}
```

Keep `const CursorAcpCapability()` valid (both fields optional). Do not import `dart:io` `File` directly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_acp_capability_test.dart test/services/cli/gemini/gemini_acp_capability_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/acp_capability.dart \
  client/lib/services/cli/cursor/capabilities/acp.dart \
  client/test/services/cli/cursor/cursor_acp_capability_test.dart \
  client/test/services/cli/gemini/gemini_acp_capability_test.dart
git commit -m "$(cat <<'EOF'
Skip Cursor ACP cursor_login when isolated auth.json has tokens.

Logged-in personal sessions already have Official credentials from
passthrough; the extra authenticate RPC was blocking the first prompt.
EOF
)"
```

---

### Task 2: Spawner uses the resolver

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_launch_wiring.dart`
- Modify: `client/test/cubits/session/acp/acp_launch_wiring_test.dart`

**Interfaces:**
- Consumes: `AcpCapability.resolveAuthenticateMethodId(Map<String, String> env)`
- Produces: `Future<String?> spawnAuthenticateMethodId(AcpCapability? capability, Map<String, String> env)` used by `productionAcpSpawner` after `initialize`

- [ ] **Step 1: Write the failing tests**

Add to `acp_launch_wiring_test.dart`. Use a tiny fake so the helper is not `if (cli == cursor)`:

```dart
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';

class _FixedAuthCapability implements AcpCapability {
  _FixedAuthCapability(this.authenticateMethodId, {this.resolved});

  @override
  final String? authenticateMethodId;
  final String? resolved;

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async {
    if (env['FORCE_SKIP'] == '1') return null;
    return resolved ?? authenticateMethodId;
  }

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable],
  ];

  @override
  AcpAgentTranslator get translator => const _NoopTranslator();

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) => Map<String, String>.of(baseEnv);
}

class _NoopTranslator implements AcpAgentTranslator {
  const _NoopTranslator();
  @override
  List<String> get flagCandidates => const [];
  @override
  List<String> get blockingClientMethods => const [];
  @override
  List<String> get notificationClientMethods => const [];
  @override
  String translateStopError(Object error, {required bool suppressAbort}) =>
      error.toString();
}

test('spawnAuthenticateMethodId uses resolver not the declared getter', () async {
  final cap = _FixedAuthCapability('cursor_login');
  expect(
    await spawnAuthenticateMethodId(cap, {'FORCE_SKIP': '1'}),
    isNull,
  );
  expect(
    await spawnAuthenticateMethodId(cap, const {}),
    'cursor_login',
  );
  expect(await spawnAuthenticateMethodId(null, const {}), isNull);
});
```

If `_NoopAcpTranslator` in `acp_launch_wiring.dart` is library-private, do not import it — keep `_NoopTranslator` in the test file as above. The fake must implement every `AcpCapability` member.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_launch_wiring_test.dart --plain-name="spawnAuthenticateMethodId"`

Expected: FAIL — `spawnAuthenticateMethodId` is undefined.

- [ ] **Step 3: Add the helper and call it from the spawner**

In `acp_launch_wiring.dart`:

```dart
Future<String?> spawnAuthenticateMethodId(
  AcpCapability? capability,
  Map<String, String> env,
) async {
  if (capability == null) return null;
  return capability.resolveAuthenticateMethodId(env);
}
```

In `productionAcpSpawner`, replace the getter lookup:

```dart
      final authenticateMethodId = await spawnAuthenticateMethodId(
        registry.capability<AcpCapability>(tool),
        env,
      );
      await raceHandshake(
        connection.initialize(
          clientName: clientName,
          clientVersion: clientVersion,
          timeout: handshakeTimeout,
        ),
        processExitCode,
        authenticating: false,
      );
      if (authenticateMethodId != null) {
        await raceHandshake(
          connection.authenticate(
            authenticateMethodId,
            timeout: handshakeTimeout,
          ),
          processExitCode,
          authenticating: true,
        );
      }
```

Keep initialize-before-authenticate order. Do not inspect `CliTool` here. `capabilityToPlan` still copies the **declared** `authenticateMethodId` getter (Cursor stays `'cursor_login'` in the plan).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_launch_wiring_test.dart test/services/cli/cursor/cursor_registry_acp_test.dart`

Expected: PASS. Registry test still expects `capabilityToPlan(cap)!.authenticateMethodId == 'cursor_login'`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_launch_wiring.dart \
  client/test/cubits/session/acp/acp_launch_wiring_test.dart
git commit -m "$(cat <<'EOF'
Use spawn-time ACP authenticate resolution instead of the declared id.

productionAcpSpawner can skip cursor_login when the capability reports
existing isolated-home tokens, without a CLI branch in the handshake.
EOF
)"
```

---

### Task 3: Analyze and targeted tests

**Files:**
- None new. Verify Tasks 1–2.

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new errors. Pre-existing `annotate_overrides` infos elsewhere are allowed.

- [ ] **Step 2: Targeted tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_acp_capability_test.dart test/services/cli/gemini/gemini_acp_capability_test.dart test/services/cli/claude/claude_acp_capability_test.dart test/services/cli/codex/codex_acp_capability_test.dart test/cubits/session/acp/acp_launch_wiring_test.dart test/services/cli/cursor/cursor_registry_acp_test.dart`

Expected: PASS.

- [ ] **Step 3: Format if analyze or CI format check would fail**

Run: `cd client && dart format lib/services/cli/registry/capabilities/acp_capability.dart lib/services/cli/cursor/capabilities/acp.dart lib/cubits/session/acp/acp_launch_wiring.dart test/services/cli/cursor/cursor_acp_capability_test.dart test/services/cli/gemini/gemini_acp_capability_test.dart test/cubits/session/acp/acp_launch_wiring_test.dart`

Commit formatting only if the command rewrote files.

- [ ] **Step 4: Do not start the full suite until claiming the branch done**

Inner loop ends here. Full `dart run tool/run_tests.dart` is the slow outer loop before merge, not per task.

# Session SSH MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mixed-workspace local seats get a managed MCP `ssh` (four tools) backed by dartssh2, implemented with `mcp_dart` on the existing loopback gateway, with a workspace toggle defaulting on.

**Architecture:** Pure helpers in `client/lib/services/ssh/mcp/` resolve targets, paths, and tool results. `mcp_dart` Streamable HTTP is mounted at `/ssh/mcp` on `TeammateBusMcpGateway` (no second bind). `composeRuntimeExtraMcpServers` injects `extra["ssh"]` for local mixed seats. Credentials stay in `SshClientFactory`; the MCP is not in the user catalog.

**Tech Stack:** Flutter/Dart, `mcp_dart ^2.4.2`, dartssh2 / `SshClientFactory`, existing TeamBus loopback HTTP, CLI extra MCP writers, l10n ARB.

**Spec:** `docs/superpowers/specs/2026-09-16-session-ssh-mcp-design.md`

---

## Global Constraints

- Never invoke `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <path> [--plain-name=...]`.
- Inner loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` plus the task's test file. Full `dart run tool/run_tests.dart` only once before claiming done, in the background if long.
- Edit `app_en.arb` and `app_zh.arb` only. Do not hand-edit generated `app_localizations*.dart`.
- Do not migrate TeamBus / catalog / team-composer onto `mcp_dart`.
- Do not add `@fangjunjie/ssh-mcp-server` or Node/`npx`.
- Inject `Filesystem` / `SshClientFactory` (or a narrow executor) — no `Directory.current`, no `print`.
- Stage only files for the current task. Do not commit unless the user asked to commit in this conversation; if they did, follow the commit step.

## File map

| Path | Responsibility |
|------|----------------|
| `client/lib/models/workspace.dart` | `injectSessionSshMcp` default true; persist only `false` |
| `client/lib/services/ssh/mcp/session_ssh_mcp_constants.dart` | name `ssh`, path `/ssh/mcp`, tool names, error codes |
| `client/lib/services/ssh/mcp/session_ssh_mcp_targets.dart` | ssh folders → targets; `connectionName` resolve |
| `client/lib/services/ssh/mcp/session_ssh_mcp_paths.dart` | local/remote path roots; cwd resolve |
| `client/lib/services/ssh/mcp/session_ssh_mcp_operations.dart` | four tools + error codes; fakeable executor |
| `client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart` | HTTP/stdio extra-server config + inject predicate |
| `client/lib/services/ssh/mcp/session_ssh_mcp_policy.dart` | Claude/Cursor allow entries |
| `client/lib/services/ssh/mcp/session_ssh_mcp_http.dart` | mcp_dart Streamable HTTP adapter |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart` | route `/ssh/mcp` before `_delegates` 400 |
| `client/lib/services/launch/session_shell_connector.dart` | pass workspace + SSH MCP URL into compose |
| `client/lib/app/app_shell.dart` | attach adapter + session resolver |
| `client/lib/repositories/session_repository.dart` + cubit/data-store/catalog | persist toggle |
| `client/lib/pages/home_workspace/workspace/workspace_info_section.dart` | mixed-only switch |
| `client/pubspec.yaml` | `mcp_dart: ^2.4.2` |
| Tests under `client/test/services/ssh/mcp/`, plus existing files listed per task |

---

### Task 1: Workspace inject toggle persistence

**Files:**
- Modify: `client/lib/models/workspace.dart`
- Test: `client/test/models/workspace_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `workspace_test.dart`:

```dart
test('injectSessionSshMcp defaults on and omits true from json', () {
  final ws = Workspace(workspaceId: 'p1', createdAt: 1);
  expect(ws.injectSessionSshMcp, isTrue);
  expect(ws.toJson().containsKey('injectSessionSshMcp'), isFalse);
  expect(Workspace.fromJson(ws.toJson()).injectSessionSshMcp, isTrue);
});

test('injectSessionSshMcp false round-trips', () {
  final ws = Workspace(
    workspaceId: 'p1',
    createdAt: 1,
    injectSessionSshMcp: false,
  );
  expect(ws.toJson()['injectSessionSshMcp'], isFalse);
  expect(Workspace.fromJson(ws.toJson()).injectSessionSshMcp, isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client
dart run tool/run_tests.dart test/models/workspace_test.dart --plain-name="injectSessionSshMcp"
```

Expected: FAIL compiling (`injectSessionSshMcp` missing).

- [ ] **Step 3: Implement the field**

Thread `injectSessionSshMcp` through `Workspace._`, public factory (default `true`), `fromJson` (`json['injectSessionSshMcp'] == false` → false, else true), `copyWith`, `toJson` (`if (!injectSessionSshMcp) 'injectSessionSshMcp': false`), `==`, `hashCode`. Follow `rootSandboxEnvOptIn` placement, inverted persistence.

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit** (only if the user asked)

```bash
git add client/lib/models/workspace.dart client/test/models/workspace_test.dart
git commit -m "$(cat <<'EOF'
feat: persist workspace Session SSH MCP inject toggle

Default on; write JSON only when the user turns it off so existing workspaces keep auto-inject.
EOF
)"
```

---

### Task 2: Constants, targets, connectionName

**Files:**
- Create: `client/lib/services/ssh/mcp/session_ssh_mcp_constants.dart`
- Create: `client/lib/services/ssh/mcp/session_ssh_mcp_targets.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_targets_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';

SshProfile profile(String id, {String name = ''}) => SshProfile(
  id: id,
  name: name.isEmpty ? id : name,
  host: '$id.example',
  username: 'alice',
);

void main() {
  test('collects unique ssh folders and skips local/wsl', () {
    final targets = sessionSshMcpTargetsFromFolders(
      folders: const [
        WorkspaceFolder(path: '/local', targetId: WorkspaceFolder.localTargetId),
        WorkspaceFolder(path: '/a', targetId: 'ssh:home'),
        WorkspaceFolder(path: '/b', targetId: 'ssh:home'),
        WorkspaceFolder(path: '/wsl', targetId: 'wsl:ubuntu'),
        WorkspaceFolder(path: '/c', targetId: 'ssh:build'),
      ],
      profileOf: (id) => switch (id) {
        'home' => profile('home', name: 'Home'),
        'build' => profile('build', name: 'Build'),
        _ => null,
      },
    );
    expect(targets.map((t) => t.profile.id), ['home', 'build']);
    expect(targets.first.folderPaths, ['/a', '/b']);
  });

  test('resolveConnectionName prefers profileId then unique name', () {
    final targets = [
      SessionSshMcpTarget(profile: profile('home', name: 'Home'), folderPaths: ['/a']),
      SessionSshMcpTarget(profile: profile('build', name: 'Build'), folderPaths: ['/c']),
    ];
    expect(resolveSessionSshMcpConnection(targets, 'home')?.profile.id, 'home');
    expect(resolveSessionSshMcpConnection(targets, 'Build')?.profile.id, 'build');
    expect(resolveSessionSshMcpConnection(targets, null)?.profile.id, isNull);
    expect(
      resolveSessionSshMcpConnection(
        [targets.first],
        null,
      )?.profile.id,
      'home',
    );
    expect(resolveSessionSshMcpConnection(targets, 'missing'), isNull);
  });

  test('duplicate display names require profileId', () {
    final targets = [
      SessionSshMcpTarget(profile: profile('a', name: 'Box'), folderPaths: ['/a']),
      SessionSshMcpTarget(profile: profile('b', name: 'Box'), folderPaths: ['/b']),
    ];
    expect(resolveSessionSshMcpConnection(targets, 'Box'), isNull);
    expect(resolveSessionSshMcpConnection(targets, 'a')?.profile.id, 'a');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_targets_test.dart
```

Expected: FAIL compiling (library missing).

- [ ] **Step 3: Implement**

`session_ssh_mcp_constants.dart`:

```dart
const sessionSshMcpServerName = 'ssh';
const sessionSshMcpPath = '/ssh/mcp';

const sessionSshMcpToolListServers = 'list-servers';
const sessionSshMcpToolExecuteCommand = 'execute-command';
const sessionSshMcpToolUpload = 'upload';
const sessionSshMcpToolDownload = 'download';

const sessionSshMcpErrorDisabled = 'ssh_mcp_disabled';
const sessionSshMcpErrorUnknownTarget = 'unknown_ssh_target';
const sessionSshMcpErrorPath = 'path_not_in_workspace';
const sessionSshMcpErrorUnavailable = 'ssh_unavailable';
const sessionSshMcpErrorTimeout = 'command_timeout';
const sessionSshMcpErrorOutputLimit = 'OUTPUT_LIMIT_EXCEEDED';
const sessionSshMcpErrorSftp = 'sftp_error';

const sessionSshMcpMaxOutputBytes = 10 * 1024 * 1024;
```

`session_ssh_mcp_targets.dart`: use `sshProfileIdOfId` / `runtimeKindOfId` from `runtime_target.dart`. Preserve first-seen profile order. Merge `folderPaths`. `resolveSessionSshMcpConnection`: trim name; empty/null → single target or null; else profileId match, then unique name match.

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 3: Path boundary helpers

**Files:**
- Create: `client/lib/services/ssh/mcp/session_ssh_mcp_paths.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_paths_test.dart`

- [ ] **Step 1: Write the failing test**

Cover: remote absolute under folder; `../` escape; relative cwd resolved against `folderPaths.first`; local path under local roots with `usesPosixPaths: true`; remote relative path rejected.

Use `workspacePathUnderFolder` from `workspace_path_utils.dart`. Remote checks always `usesPosixPaths: true`.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_paths_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement**

```dart
String? resolveSessionSshMcpRemoteCwd({
  String? cwd,
  required List<String> folderPaths,
}) { ... }

bool sessionSshMcpRemotePathAllowed(String path, List<String> folderPaths);

bool sessionSshMcpLocalPathAllowed(
  String path,
  List<String> roots, {
  required bool usesPosixPaths,
});
```

Relative `cwd` join with posix context onto `folderPaths.first`. Empty `folderPaths` → not allowed. After normalize, require `workspacePathUnderFolder` against some root.

Also add:

```dart
String sessionSshMcpPosixQuote(String value) =>
    "'${value.replaceAll("'", r"'\''")}'";
```

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 4: Tool operations with fake SSH

**Files:**
- Create: `client/lib/services/ssh/mcp/session_ssh_mcp_operations.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_operations_test.dart`

Do not call mcp_dart here. Return a small result type the HTTP adapter will wrap.

```dart
class SessionSshMcpToolResult {
  const SessionSshMcpToolResult.ok(this.text) : code = null;
  const SessionSshMcpToolResult.error(this.code, this.text);
  final String? code;
  final String text;
  bool get isError => code != null;
}

abstract class SessionSshMcpExecutor {
  Future<({int? exitCode, String stdout, String stderr})> runCommand({
    required SshProfile profile,
    required String command,
    required Duration timeout,
  });
  Future<void> upload({
    required SshProfile profile,
    required List<int> bytes,
    required String remotePath,
  });
  Future<List<int>> download({
    required SshProfile profile,
    required String remotePath,
  });
}

class SessionSshMcpContext {
  const SessionSshMcpContext({
    required this.enabled,
    required this.targets,
    required this.localAllowedRoots,
    required this.localUsesPosixPaths,
    required this.localFs,
  });
  final bool enabled;
  final List<SessionSshMcpTarget> targets;
  final List<String> localAllowedRoots;
  final bool localUsesPosixPaths;
  final Filesystem localFs;
}
```

- [ ] **Step 1: Write the failing tests**

Fake executor records last command/profile. Cases from the spec:

- `enabled: false` → `ssh_mcp_disabled` for every tool
- `list-servers` JSON list, no password fields
- one target, omit `connectionName` on execute
- two targets, omit name → `unknown_ssh_target`
- execute quotes cwd via `LaunchCommandBuilder` posix quoting (`cd -- '...' && cmd`) and calls executor
- timeout from executor `TimeoutException` → `command_timeout`
- stdout+stderr > 10MiB → `OUTPUT_LIMIT_EXCEEDED` (fake can return a huge string; test may use a smaller injected limit parameter `maxOutputBytes` defaulting to the constant so the test does not allocate 10MiB — **add `maxOutputBytes` on operations constructor**, default `sessionSshMcpMaxOutputBytes`, test with `8`)
- upload/download success inside roots; `../` → `path_not_in_workspace`
- executor throw → `ssh_unavailable` / `sftp_error` without putting `secret` in the message even if the exception contains it (sanitize: use `error.runtimeType` / public SSH errors only)

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_operations_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement operations**

`execute-command`: resolve target; resolve cwd; if cwd not allowed → path error; quote cwd with `sessionSshMcpPosixQuote`. Command is `'cd -- $quoted && $cmdString'`. Reject empty `cmdString`.

Output cap: if `utf8.encode(stdout).length + utf8.encode(stderr).length > maxOutputBytes`, return error with truncated combined text.

`list-servers`: `jsonEncode` of maps with `profileId, name, host, port, username, folderPaths` only.

Upload: `localFs.readBytes` after local path check; executor.upload. Download: executor.download then `localFs.writeBytes` after local path check (create parent dir via `ensureDir`).

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 5: Transport config and inject predicate

**Files:**
- Create: `client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_transport_test.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart` (`composeRuntimeExtraMcpServers` + `_extraMcpServersWithCatalog`)
- Modify: `client/test/services/session/team_generation_session_resources_test.dart` only if signature requires new args — keep them optional so this test stays green without SSH inject

- [ ] **Step 1: Write the failing transport tests**

Mirror `catalog_mcp_transport_test.dart` fakes (`TeamBehaviorCapability` + `CliToolRegistry`).

`shouldInjectSessionSshMcp({required Workspace workspace, required RuntimeKind launchKind})`:

- mixed + default toggle + local + ssh folder → true
- local-only / remote-only / remote launchKind / toggle false / no ssh folder → false
- mixed + wsl launchKind + ssh folder → true (`!usesSshTransport`)

`resolveSessionSshMcpTransportConfig` (copy catalog resolver, but URL is `sessionSshEndpoint`, no team-generation token, no remoteBinding tunnel branch — **local seats only**; if someone passes remoteBinding, still do not inject SSH MCP).

`extraMcpServersWithSessionSsh`: if `shouldInject` then `{...extra, 'ssh': config}`.

Claude native + bridge path: stdio `teammateBusMcpServerConfigStdio` with `--bus-url` equal to `http://127.0.0.1:9/ssh/mcp`.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_transport_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement transport + wire compose**

Add optional params to `composeRuntimeExtraMcpServers`:

```dart
Workspace? workspace,
Uri? sessionSshMcpEndpoint,
```

After catalog/composer merge:

```dart
if (workspace != null &&
    sessionSshMcpEndpoint != null &&
    shouldInjectSessionSshMcp(
      workspace: workspace,
      launchKind: launchKind,
    )) {
  return extraMcpServersWithSessionSsh(
    extra: servers,
    config: resolveSessionSshMcpTransportConfig(
      cliRegistry: cliRegistry,
      sessionSshMcpEndpoint: sessionSshMcpEndpoint,
      sessionId: session.sessionId,
      memberId: memberId,
      cli: cli,
      isLocalNative: isLocalNative,
    ),
  );
}
```

Pass `workspace` and `_host.teammateBusMcpGateway.sessionSshMcpEndpoint` from `_extraMcpServersWithCatalog` (add those fields). Add `Uri get sessionSshMcpEndpoint` on the gateway in Task 7; **for this task** use a getter that throws if HTTP not started, same as `catalogMcpEndpoint`. If Task 7 is not done yet, add the getter now:

```dart
Uri get sessionSshMcpEndpoint =>
    Uri.parse('http://127.0.0.1:${_http!.port}$sessionSshMcpPath');
```

Do not route the path yet (404 until Task 7). Tests for compose live in the transport test by calling `composeRuntimeExtraMcpServers` with a mixed workspace.

- [ ] **Step 4: Run tests**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_transport_test.dart
dart run tool/run_tests.dart test/services/session/team_generation_session_resources_test.dart
```

Expected: PASS. Builder compose keys unchanged (no workspace passed → no `ssh`).

- [ ] **Step 5: Commit** (only if asked)

---

### Task 6: Claude/Cursor allow entries

**Files:**
- Create: `client/lib/services/ssh/mcp/session_ssh_mcp_policy.dart`
- Modify: `client/lib/services/session/member_role_provision.dart`
- Modify: `client/lib/services/cli/claude/capabilities/provider.dart` (immediately after `applyCatalogReadAllows`)
- Modify: `client/lib/services/cli/flashskyai/capabilities/provider.dart` (same)
- Modify: `client/lib/services/cli/cursor/provider/cursor_cli_config_policy.dart`
- Modify: `client/lib/services/cli/cursor/capabilities/cli_config_merger.dart`
- Modify: `client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart` (`_mergeCatalogReadPermissions` and `mergeMemberConfig` path)
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_policy_test.dart`
- Test: `client/test/services/session/member_role_provision_test.dart`
- Test: `client/test/services/provider/cursor/cursor_cli_config_policy_test.dart`

Merge the four SSH allow entries in the **same places catalog read allows are merged**. Extra `mcp__ssh__*` / `Mcp(ssh:…)` lines are inert when `extraMcpServers` has no `ssh` key. Do not thread `extraMcpServers` through the permission writers.

- [ ] **Step 1: Policy unit test**

```dart
expect(
  SessionSshMcpPolicy.claudeAllowEntries,
  containsAll([
    'mcp__ssh__list-servers',
    'mcp__ssh__execute-command',
    'mcp__ssh__upload',
    'mcp__ssh__download',
  ]),
);
expect(
  SessionSshMcpPolicy.cursorAllowEntries,
  containsAll([
    'Mcp(ssh:list-servers)',
    'Mcp(ssh:execute-command)',
    'Mcp(ssh:upload)',
    'Mcp(ssh:download)',
  ]),
);
```

Add `MemberRoleProvision.applySessionSshMcpAllows` copying `applyCatalogReadAllows`. Add `CursorCliConfigPolicy.applySessionSshMcpPolicy` copying `applyCatalogReadPolicy`. Test both merge the four entries and keep existing allow lines.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_policy_test.dart
```

Expected: FAIL compiling.

- [ ] **Step 3: Implement policy and call it from the catalog-allow call sites listed above**

- [ ] **Step 4: Run related tests**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_policy_test.dart
dart run tool/run_tests.dart test/services/session/member_role_provision_test.dart
dart run tool/run_tests.dart test/services/provider/cursor/cursor_cli_config_policy_test.dart
```

Expected: PASS. Existing catalog-allow assertions still hold; SSH entries are additional.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 7: mcp_dart HTTP adapter + gateway route

**Files:**
- Modify: `client/pubspec.yaml` — `mcp_dart: ^2.4.2` then `cd client && flutter pub get`
- Create: `client/lib/services/ssh/mcp/session_ssh_mcp_http.dart`
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_gateway_test.dart`

Follow mcp_dart's streamable HTTP example: a `Map<String, StreamableHTTPServerTransport>` keyed by MCP session id. Each new initialize creates a transport + `McpServer` whose four tools delegate to shared `SessionSshMcpOperations`. Read `X-Session` / `X-Member` from the `HttpRequest` (pass into tool closures via a zone or per-request holder on the adapter).

`allowedHosts`: `{ '127.0.0.1', 'localhost' }`. `enableDnsRebindingProtection: true`.

Gateway `_onRequest`: **before** catalog is fine, but **must be before** the missing-session 400, like catalog:

```dart
if (request.uri.path == sessionSshMcpPath) {
  final adapter = _sessionSshMcp;
  if (adapter == null) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }
  await adapter.handle(request);
  return;
}
```

Handle GET/POST/DELETE (not POST-only). `attachSessionSshMcp(SessionSshMcpHttpAdapter adapter)`.

Missing `X-Session`: still `handleRequest`; tool/initialize path must yield **HTTP 200** with JSON-RPC or tool error, never 400. If mcp_dart initialize succeeds without tools, make `tools/call` and `tools/list` check session and return `isError` / JSON-RPC error.

Illegal Host: 403 from transport or adapter; do not dispatch tools.

- [ ] **Step 1: Add dependency and a failing gateway test**

`setUpAll(() { HttpOverrides.global = null; });` like `catalog_mcp_gateway_test.dart`.

Attach adapter with resolver:

- `sess-1` → enabled mixed context, one fake target, fake executor
- missing header → 200 + error

POST `initialize` then `tools/list` (include `Accept: application/json, text/event-stream` if mcp_dart requires it). Expect tool names to include `list-servers`.

Also assert `POST /mcp` with no TeamBus register still 400 (copy catalog test).

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client
flutter pub get
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_gateway_test.dart
```

Expected: FAIL (no route / no adapter).

- [ ] **Step 3: Implement adapter + route**

Register tools with mcp_dart `JsonSchema.object`. Map `SessionSshMcpToolResult.isError` to `CallToolResult(isError: true, content: [TextContent(...)])`. Prefix error `text` with `code:` so tests can `contains('unknown_ssh_target')`.

Production executor wrapping `SshClientFactory`:

```dart
class SshClientFactorySessionSshMcpExecutor implements SessionSshMcpExecutor {
  SshClientFactorySessionSshMcpExecutor(this._factory);
  final SshClientFactory _factory;
  // runOnStorage; sftpFor + same open/writeBytes/read as RemoteFileStore
}
```

Keep this executor in `session_ssh_mcp_executor.dart` so HTTP file stays transport-only.

- [ ] **Step 4: Run tests**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_gateway_test.dart
dart run tool/run_tests.dart test/services/catalog/catalog_mcp_gateway_test.dart
dart run tool/run_tests.dart test/services/team_bus/mcp/teammate_bus_mcp_gateway_test.dart
```

Expected: PASS. Catalog and TeamBus routes unchanged.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 8: App-shell attach and session resolver

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Create helper if the resolver is >40 lines: `client/lib/services/ssh/mcp/session_ssh_mcp_resolver.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_resolver_test.dart` (pure: given session+workspace+profiles, build `SessionSshMcpContext`)

Resolver rules:

- Find `AppSession` by id; find `Workspace` by `session.workspaceId`
- `enabled` = `shouldInjectSessionSshMcp(workspace: workspace, launchKind: RuntimeKind.local)` — **the HTTP server only serves local CLI clients**; if the workspace would not inject, tools return `ssh_mcp_disabled` even if a stale MCP config still points here
- Targets from folders + `SshProfileRepository.findById`
- `localAllowedRoots` = every local (`WorkspaceFolder.localTargetId`) folder path, plus that member's `session.workDirsForMember` (cwd and add-dirs) when `memberId` is non-empty. Deduplicate.
- `localFs` = home-plane `LocalFilesystem` / `HomeStorage` filesystem (injected)
- `localUsesPosixPaths` from storage

`app_shell.dart`: after `attachCatalogHandler`, `attachSessionSshMcp` with real `SshClientFactory` already constructed for SSH. Use the same `sshClientFactory` / profile repo / session+workspace lookup ChatCubit uses. If ChatCubit is created after the gateway, attach in the same block that attaches catalog (catalog already resolves sessions via `catalogRuntime.resolveSession`). Extend that pattern: either add `resolveSessionSshMcp` on a small runtime object or a closure capturing repositories.

Do not construct a second `HttpServer`.

- [ ] **Step 1: Resolver unit tests** (mixed vs toggle off vs missing profile skipped)

- [ ] **Step 2: Run to fail / Step 3 implement / Step 4 pass**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_resolver_test.dart
```

- [ ] **Step 5: Commit** (only if asked)

---

### Task 9: Persist toggle through repository and Info UI

**Files:**
- Modify: `client/lib/repositories/session_repository.dart` — `updateWorkspaceMetadata(..., bool? injectSessionSshMcp)`
- Modify: `client/lib/cubits/chat/session_data_store.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/services/catalog/workspace_catalog.dart` (same named param if it duplicates metadata update)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_info_section.dart`
- Test: `client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`
- Add repository test coverage in existing session repository / workspace tests if there is already `updateWorkspaceMetadata` coverage; otherwise a focused `session_repository` test for the new field

l10n keys (ARB only):

```json
"injectSessionSshMcpTitle": "Inject Session SSH MCP for local members",
"injectSessionSshMcpSubtitle": "Local seats can run commands and transfer files on this workspace's remote machines. Reconnect sessions after changing.",
"injectSessionSshMcpTitle": "为本地成员注入 Session SSH MCP",
"injectSessionSshMcpSubtitle": "本机座位可通过 MCP 在本工作区的远程机器上执行命令和传文件。更改后需重连 session。"
```

(English in `app_en.arb`, Chinese in `app_zh.arb` — do not duplicate keys in one file.)

UI: next to `WorkspaceRootSandboxEnvOptInCard`. Show only when `workspaceTopologyOf(live.folders) == WorkspaceTopology.mixed`. `Switch` bound to `live.injectSessionSshMcp`; `onChanged` → `ChatCubit.updateWorkspaceMetadata(..., injectSessionSshMcp: next)`. No extra confirm dialog (unlike root sandbox).

- [ ] **Step 1: Failing widget tests**

In `workspace_info_section_target_test.dart`:

- Local-only workspace: `find.text(l10n.injectSessionSshMcpTitle)` finds nothing
- Mixed (local folder + `ssh:home`): finds the title

Need `SshProfile` / runtime targets already provided by `_pumpWorkspaceInfo` if folders use `ssh:`. Follow how that pump registers SSH profiles (read the existing helper at the bottom of the test file; add a profile if required for the folders editor, not for the switch).

- [ ] **Step 2: Run to fail**

```bash
cd client
dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_info_section_target_test.dart
```

Expected: FAIL missing l10n or missing widget.

- [ ] **Step 3: Implement plumbing + UI**

- [ ] **Step 4: Re-run widget test + `workspace_test`**

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 10: Analyze and full suite

- [ ] **Step 1: Analyze**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no issues in new files. Fix any you introduced.

- [ ] **Step 2: Targeted regression**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp
dart run tool/run_tests.dart test/services/catalog/catalog_mcp_gateway_test.dart
dart run tool/run_tests.dart test/services/launch/session_shell_connector.dart
```

If `session_shell_connector` has no test file at that path, run `test/services/session/team_generation_session_resources_test.dart` instead.

- [ ] **Step 3: Full suite once** (background before claiming done)

```bash
cd client
dart run tool/run_tests.dart
```

Expected: PASS.

- [ ] **Step 4: Commit** remaining wiring (only if asked)

---

## Spec coverage (self-review)

| Spec item | Task |
|-----------|------|
| Mixed + local + ssh folder + toggle | 5 |
| No inject: local/remote/remote seat/toggle off/no ssh | 5 |
| Default on JSON omit / false persist | 1, 9 |
| One MCP `ssh`, four tools | 4, 7 |
| dartssh2 pool, no npx | 7 executor |
| mcp_dart only on `/ssh/mcp` | 7 |
| list-servers shape / connectionName | 2, 4 |
| cwd / 10MiB / timeout codes | 4 |
| path roots | 3, 4 |
| HTTP 200 missing session | 7 |
| stdio bridge `--bus-url` `/ssh/mcp` | 5 |
| Claude/Cursor allow entries (same sites as catalog reads) | 6 |
| Info switch mixed-only | 9 |
| App attach / resolver | 8 |
| No TeamBus migration / no remote tunnel | 7 tests keep `/mcp` 400 |

## Out of scope (do not implement)

Command allow/deny lists, SOCKS, bastion shell, 2FA, `~/.ssh/config`, user MCP catalog entry, remote-seat injection, WSL-as-SSH-target in `list-servers`.

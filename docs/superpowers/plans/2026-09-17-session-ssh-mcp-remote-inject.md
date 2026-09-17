# Session SSH MCP remote-seat inject Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject the existing in-process Session SSH MCP into remote seats (and pure-remote workspaces) through catalog's idle HTTP tunnel, so every seat can reach every `ssh:*` folder in the workspace.

**Architecture:** Keep `/ssh/mcp` on the existing loopback gateway. Workspace enablement is toggle + at least one `ssh:*` folder. Local seats still get gateway HTTP or `teammate_bus_bridge` stdio. Remote seats (`ssh` / `termux`) get `http://127.0.0.1:<idleHttpTunnelPort>/ssh/mcp` plus `X-Bus-Token`, matching catalog. No second tunnel, no remote MCP process, no tool-contract change.

**Tech Stack:** Flutter/Dart, existing `mcp_dart` SSH MCP, `RemoteBusBinding` idle HTTP tunnel, CLI extra MCP writers, l10n ARB.

**Spec:** `docs/superpowers/specs/2026-09-16-session-ssh-mcp-design.md`

---

## Global Constraints

- Never invoke `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <path> [--plain-name=...]`.
- Inner loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` plus the task's test file. Full `dart run tool/run_tests.dart` only once before claiming done, in the background if long.
- Edit `app_en.arb` and `app_zh.arb` only. Do not hand-edit generated `app_localizations*.dart` (regenerate with `flutter gen-l10n` / test).
- Do not add a dedicated SSH MCP tunnel, a remote MCP process, or `X-Bus-Token` validation on `/ssh/mcp`.
- Do not change the four tools, path rules, or `localPath` meaning (always App home plane).
- Do not migrate TeamBus / catalog / team-composer onto `mcp_dart`.
- Stage only files for the current task. Do not touch unrelated dirty files (`apply_plan_ssh_compiler.dart`, `work_path_projector.dart`, `workspace_cli_cache.dart`, etc.).
- Do not commit unless the user asked to commit in this conversation; if they did, follow the commit step.

## File map

| Path | Responsibility |
|------|----------------|
| `client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart` | `workspaceHasSshMcpFolder` / `workspaceSessionSshMcpEnabled` / inject predicate; remote `remoteBinding` HTTP config |
| `client/lib/services/ssh/mcp/session_ssh_mcp_resolver.dart` | Handler `enabled` uses workspace predicate |
| `client/lib/services/launch/session_shell_connector.dart` | Pass `remoteBinding` into SSH MCP resolve; tunnel-omit guard lives in `shouldInjectSessionSshMcp` |
| `client/lib/pages/home_workspace/workspace/workspace_info_section.dart` | Show toggle when workspace has `ssh:*` |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Toggle copy no longer says local-only |
| Tests listed per task | |

Do not modify gateway routing, mcp_dart adapter, tool operations, or `SessionSshMcpPolicy`.

---

### Task 1: Remote transport config (catalog-shaped)

**Files:**
- Modify: `client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_transport_test.dart`

**Interfaces:**
- Consumes: `RemoteBusBinding` (`token`, `idleHttpTunnelPort`), `sessionSshMcpPath` (`/ssh/mcp`), `teammateBusTokenHeader`
- Produces: `resolveSessionSshMcpTransportConfig(..., {RemoteBusBinding? remoteBinding})` — when `remoteBinding != null`, HTTP tunnel URL + token, never stdio

- [ ] **Step 1: Write the failing tests**

Add import:

```dart
import 'package:teampilot/services/team_bus/remote/member_bus_mcp_config.dart';
```

Extend the existing `resolve` helper with `RemoteBusBinding? remoteBinding` and pass it through. Append:

```dart
  test(
    'remote uses idle HTTP port + /ssh/mcp + token, never stdio',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
        mcpRawTunnelPort: 19090,
        mcpRelayArgv: ['/usr/bin/teammate_bus_relay', '--port', '19090'],
      );
      final cfg = resolve(
        supportsBridge: true,
        remoteBinding: remote,
        bridgeLocator: () => '/opt/teampilot/teammate_bus_bridge',
      );

      expect(cfg['type'], 'http');
      expect(cfg['url'], 'http://127.0.0.1:18080$sessionSshMcpPath');
      expect(cfg['command'], isNull);
      expect(cfg['args'], isNull);
      final headers = cfg['headers'] as Map;
      expect(headers[teammateBusMcpSessionHeader], 'sess-1');
      expect(headers[teammateBusMcpMemberHeader], 'member-1');
      expect(headers[teammateBusTokenHeader], 'bus-tok');
    },
  );
```

Keep existing local HTTP / stdio tests unchanged.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_transport_test.dart --plain-name="remote uses idle HTTP port"
```

Expected: FAIL (named param `remoteBinding` is not defined).

- [ ] **Step 3: Add the remoteBinding branch**

In `session_ssh_mcp_transport.dart`:

- Import `../../team_bus/remote/member_bus_mcp_config.dart`.
- Add optional `RemoteBusBinding? remoteBinding` to `resolveSessionSshMcpTransportConfig`.
- At the top of the function, before stdio/local HTTP:

```dart
  if (remoteBinding != null) {
    return {
      'type': 'http',
      'url':
          'http://127.0.0.1:${remoteBinding.idleHttpTunnelPort}$sessionSshMcpPath',
      'headers': <String, String>{
        teammateBusMcpMemberHeader: memberId,
        teammateBusMcpSessionHeader: sessionId,
        teammateBusTokenHeader: remoteBinding.token,
      },
    };
  }
```

Do not change `shouldInjectSessionSshMcp` in this task. Update the doc comment: local stdio/HTTP when `remoteBinding` is null; remote always HTTP over the idle tunnel.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_transport_test.dart
```

Expected: PASS (existing local tests + new remote test).

- [ ] **Step 5: Commit** (only if the user asked)

```bash
git add client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart client/test/services/ssh/mcp/session_ssh_mcp_transport_test.dart
git commit -m "$(cat <<'EOF'
feat: resolve Session SSH MCP over the idle HTTP tunnel

Remote seats need the same catalog-shaped URL and bus token so the CLI can reach /ssh/mcp.
EOF
)"
```

---

### Task 2: Workspace enablement + compose inject for remote seats

**Files:**
- Modify: `client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart`
- Modify: `client/lib/services/ssh/mcp/session_ssh_mcp_resolver.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart` (`composeRuntimeExtraMcpServers` only)
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_transport_test.dart`
- Test: `client/test/services/ssh/mcp/session_ssh_mcp_resolver_test.dart`

**Interfaces:**
- Consumes: Task 1 `remoteBinding` on resolve; compose already computes `remoteBinding` via `_catalogRemoteBindingForRuntime`
- Produces:
  - `bool workspaceHasSshMcpFolder(Workspace workspace)`
  - `bool workspaceSessionSshMcpEnabled(Workspace workspace)` — toggle + has `ssh:*`
  - `bool shouldInjectSessionSshMcp({required Workspace workspace, required RuntimeKind launchKind, RemoteBusBinding? remoteBinding})` — workspace enabled, and if `usesSshTransport(launchKind)` then `remoteBinding != null`

- [ ] **Step 1: Write the failing tests**

In `session_ssh_mcp_transport_test.dart`:

Add helper:

```dart
Workspace _remoteOnlySsh({bool injectSessionSshMcp = true}) => _workspace(
  injectSessionSshMcp: injectSessionSshMcp,
  folders: const [WorkspaceFolder(path: '/home', targetId: 'ssh:home')],
);
```

Extend `compose` with `RemoteBusBinding? mixedRemoteBinding` and pass it to `composeRuntimeExtraMcpServers`.

Replace these two tests:

- `shouldInject is false for remote-only ssh folders` → expect **true** (rename to `shouldInject is true for remote-only ssh folders`).
- `shouldInject is false when launch uses SSH transport` → split into:

```dart
  test('shouldInject is false when SSH launch has no remoteBinding', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(),
        launchKind: RuntimeKind.ssh,
      ),
      isFalse,
    );
  });

  test('shouldInject is true when SSH launch has remoteBinding', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(),
        launchKind: RuntimeKind.ssh,
        remoteBinding: const RemoteBusBinding(
          token: 'tok',
          idleHttpTunnelPort: 18080,
        ),
      ),
      isTrue,
    );
  });

  test('shouldInject is true for termux launch with remoteBinding', () {
    expect(
      shouldInjectSessionSshMcp(
        workspace: _mixedLocalSsh(),
        launchKind: RuntimeKind.termux,
        remoteBinding: const RemoteBusBinding(
          token: 'tok',
          idleHttpTunnelPort: 18080,
        ),
      ),
      isTrue,
    );
  });
```

Keep `composeRuntimeExtraMcpServers omits ssh when launchKind is ssh` (no binding). Add:

```dart
  test(
    'compose injects ssh tunnel URL for SSH launch with remoteBinding',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
      );
      final merged = compose(
        workspace: _mixedLocalSsh(),
        sessionSshMcpEndpoint: sessionSshUri,
        launchKind: RuntimeKind.ssh,
        mixedRemoteBinding: remote,
      );

      expect(merged.containsKey(sessionSshMcpServerName), isTrue);
      expect(
        merged[sessionSshMcpServerName]?['url'],
        'http://127.0.0.1:18080$sessionSshMcpPath',
      );
      final headers = merged[sessionSshMcpServerName]?['headers'] as Map;
      expect(headers[teammateBusTokenHeader], 'bus-tok');
      expect(headers[teammateBusMcpSessionHeader], 'sess-1');
      expect(headers[teammateBusMcpMemberHeader], 'member-1');
    },
  );

  test(
    'compose injects ssh for remote-only workspace on local launch',
    () {
      final merged = compose(
        workspace: _remoteOnlySsh(),
        sessionSshMcpEndpoint: sessionSshUri,
      );

      expect(merged.containsKey(sessionSshMcpServerName), isTrue);
      expect(merged[sessionSshMcpServerName]?['url'], sessionSshEndpoint);
    },
  );

  test(
    'compose injects ssh tunnel URL for remote-only workspace on SSH launch',
    () {
      const remote = RemoteBusBinding(
        token: 'bus-tok',
        idleHttpTunnelPort: 18080,
      );
      final merged = compose(
        workspace: _remoteOnlySsh(),
        sessionSshMcpEndpoint: sessionSshUri,
        launchKind: RuntimeKind.ssh,
        mixedRemoteBinding: remote,
      );

      expect(
        merged[sessionSshMcpServerName]?['url'],
        'http://127.0.0.1:18080$sessionSshMcpPath',
      );
    },
  );
```

Also add:

```dart
  test('workspaceSessionSshMcpEnabled is true for remote-only ssh folders', () {
    expect(workspaceSessionSshMcpEnabled(_remoteOnlySsh()), isTrue);
  });

  test('workspaceHasSshMcpFolder is false for local-only', () {
    expect(
      workspaceHasSshMcpFolder(
        _workspace(
          folders: const [
            WorkspaceFolder(
              path: '/local',
              targetId: WorkspaceFolder.localTargetId,
            ),
          ],
        ),
      ),
      isFalse,
    );
  });
```

In `session_ssh_mcp_resolver_test.dart`, add:

```dart
  test('pure remote ssh workspace resolves enabled', () {
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws',
      createdAt: 1,
    );
    final workspace = _workspace(
      folders: const [WorkspaceFolder(path: '/home', targetId: 'ssh:home')],
    );
    final home = _profile('home');

    final context = resolveSessionSshMcpContext(
      session: session,
      workspace: workspace,
      profileOf: (_) => home,
      localFs: localFs,
      localUsesPosixPaths: true,
    );

    expect(context.enabled, isTrue);
    expect(context.targets.map((t) => t.profile.id), ['home']);
  });
```

Keep `enabled uses local launch kind only` (local-only still `enabled: false`). Optional: rename that test to `local-only workspace resolves enabled false`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_transport_test.dart --plain-name="shouldInject is true for remote-only"
```

Expected: FAIL (`shouldInject` still false for remote-only).

- [ ] **Step 3: Implement predicates, compose wiring, resolver**

Replace `shouldInjectSessionSshMcp` in `session_ssh_mcp_transport.dart` (drop `workspace_topology.dart` import if unused):

```dart
bool workspaceHasSshMcpFolder(Workspace workspace) {
  for (final folder in workspace.folders) {
    if (runtimeKindOfId(folder.targetId) == RuntimeKind.ssh) return true;
  }
  return false;
}

bool workspaceSessionSshMcpEnabled(Workspace workspace) {
  return workspace.injectSessionSshMcp && workspaceHasSshMcpFolder(workspace);
}

bool shouldInjectSessionSshMcp({
  required Workspace workspace,
  required RuntimeKind launchKind,
  RemoteBusBinding? remoteBinding,
}) {
  if (!workspaceSessionSshMcpEnabled(workspace)) return false;
  if (usesSshTransport(launchKind) && remoteBinding == null) return false;
  return true;
}
```

In `composeRuntimeExtraMcpServers`, change the SSH inject block to:

```dart
  if (workspace != null &&
      sessionSshMcpEndpoint != null &&
      shouldInjectSessionSshMcp(
        workspace: workspace,
        launchKind: launchKind,
        remoteBinding: remoteBinding,
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
        remoteBinding: usesSshTransport(launchKind) ? remoteBinding : null,
      ),
    );
  }
```

Pass `remoteBinding` into resolve only when `usesSshTransport(launchKind)` so a local seat never gets a remote loopback port. `shouldInject` still uses the catalog-computed `remoteBinding` for the omit-if-no-tunnel guard. Remote seats without a tunnel omit `ssh`.

In `resolveSessionSshMcpContext`, set:

```dart
    enabled: workspaceSessionSshMcpEnabled(workspace),
```

Do not pass `launchKind: RuntimeKind.local`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_transport_test.dart
dart run tool/run_tests.dart test/services/ssh/mcp/session_ssh_mcp_resolver_test.dart
```

Expected: analyze clean; both files PASS.

Also run existing SSH MCP tests that should still pass:

```bash
cd client
dart run tool/run_tests.dart test/services/ssh/mcp/
```

Expected: PASS. `ssh_mcp_disabled` still comes from `context.enabled == false` (toggle off or no `ssh:*`).

- [ ] **Step 5: Commit** (only if the user asked)

```bash
git add client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart client/lib/services/ssh/mcp/session_ssh_mcp_resolver.dart client/lib/services/launch/session_shell_connector.dart client/test/services/ssh/mcp/session_ssh_mcp_transport_test.dart client/test/services/ssh/mcp/session_ssh_mcp_resolver_test.dart
git commit -m "$(cat <<'EOF'
feat: inject Session SSH MCP for remote seats and pure-remote workspaces

Remote CLIs reach /ssh/mcp through the existing idle HTTP tunnel so mixed and multi-host remote seats can use other SSH machines.
EOF
)"
```

---

### Task 3: Info toggle visibility and copy

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_info_section.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart`

**Interfaces:**
- Consumes: `workspaceHasSshMcpFolder` from Task 2
- Produces: toggle visible for any workspace with `ssh:*` (including pure remote); ARB copy no longer says local-only

- [ ] **Step 1: Write the failing test**

In `workspace_info_section_target_test.dart`, keep the local-only test that expects the title `findsNothing`. Keep the mixed test that expects `findsOneWidget`. Add:

```dart
  testWidgets(
    'WorkspaceInfoSection shows inject Session SSH MCP toggle for remote-only ssh folders',
    (tester) async {
      await tester.runAsync(() async {
        await _pumpWorkspaceInfo(
          tester,
          workspace: Workspace(
            workspaceId: 'w1',
            folders: const [
              WorkspaceFolder(path: '/home', targetId: 'ssh:home'),
            ],
            createdAt: 1,
          ),
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(find.text(l10n.injectSessionSshMcpTitle), findsOneWidget);
      });
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client
dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_info_section_target_test.dart --plain-name="remote-only ssh folders"
```

Expected: FAIL (`findsNothing` / title not shown because UI still requires mixed).

- [ ] **Step 3: Show toggle on `ssh:*` and update ARB**

In `workspace_info_section.dart`, import `session_ssh_mcp_transport.dart` and replace the mixed-only guard:

```dart
          if (workspaceHasSshMcpFolder(live)) ...[
            const SizedBox(height: 12),
            TpCard.outlined(
              child: WorkspaceInjectSessionSshMcpCard(workspace: live),
            ),
          ],
```

Leave `workspaceTopologyOf` for the topology chip.

ARB (keys unchanged):

`app_en.arb`:

```json
  "injectSessionSshMcpTitle": "Inject Session SSH MCP",
  "injectSessionSshMcpSubtitle": "Local and remote seats can run commands and transfer files on this workspace's SSH machines via MCP. Reconnect sessions after changing.",
```

`app_zh.arb`:

```json
  "injectSessionSshMcpTitle": "注入 Session SSH MCP",
  "injectSessionSshMcpSubtitle": "本机和远程座位都可通过 MCP 在本工作区的 SSH 机器上执行命令和传文件。更改后需重连 session。",
```

Do not hand-edit `app_localizations*.dart`. `flutter gen-l10n` / the next test run regenerates them (`generate: true` in `pubspec.yaml`).

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_info_section_target_test.dart
dart run tool/run_tests.dart test/services/ssh/mcp/
```

Expected: PASS.

- [ ] **Step 5: Commit** (only if the user asked)

```bash
git add client/lib/pages/home_workspace/workspace/workspace_info_section.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart
git commit -m "$(cat <<'EOF'
feat: show Session SSH MCP toggle for any workspace with SSH folders

Pure-remote workspaces need the same switch, and the copy should cover remote seats.
EOF
)"
```

If generated l10n files did not change on disk, omit them from `git add`.

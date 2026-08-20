# TeamPilot Catalog MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every session a `teampilot` MCP plus a managed `teampilot-catalog` skill so the agent can search/install/import/create/update/unbind/delete the same skill, plugin, and MCP catalogs the UI uses, bound to the current workspace.

**Architecture:** Kind modules register tools; `CatalogMcpHandler` serves `/catalog/mcp` on the existing loopback gateway without TeamBus registration; mutations go through repositories/acquisition engines and `CatalogMutationBus`; launch injects the MCP extra-server and a managed skill/prompt on every connect. Current session does not hot-apply (`restart_required: true`).

**Tech Stack:** Dart / Flutter (`flutter_test`), existing MCP JSON-RPC (`JsonRpcRequest` / `McpToolResponse`), `AppStorage.installForTesting`, Skill/Plugin/MCP repositories.

**Spec:** `docs/superpowers/specs/2026-08-19-teampilot-catalog-mcp-design.md`

## Global Constraints

- Verify with `cd client && flutter test <task files>` after each task; before claiming the whole feature done also run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- Do not call cubits from catalog modules; emit `CatalogMutationBus` only
- `bind_to` other than `workspace` → `CatalogException('bind_scope_unsupported', ...)`
- Mutating tools are not pre-allowed; read tools are
- Do not add catalog tools to `teammate-bus`
- Do not expose `create_plugin`
- Prompt kind is out of scope
- Managed skill is not user-uninstallable (not in `skills/installed` manifest)
- Stdio catalog transport reuses `teammate_bus_bridge` with `--bus-url` set to the catalog URL (no new bridge flag)
- Commit per task; messages `feat:` / `fix:` / `test:`
- No new l10n (agent-facing English strings)

## File map

Create:

- `client/lib/services/catalog/catalog_mcp_constants.dart` — server name, path, headers
- `client/lib/services/catalog/catalog_kind.dart` — op/request/result/exception/module interface/tool spec
- `client/lib/services/catalog/catalog_kind_registry.dart` — register + `list_installed` + dispatch
- `client/lib/services/catalog/catalog_mcp_policy.dart` — read vs mutate names + CLI allow entries
- `client/lib/services/catalog/catalog_mutation_bus.dart`
- `client/lib/services/catalog/catalog_workspace_binder.dart`
- `client/lib/services/catalog/catalog_path_sandbox.dart`
- `client/lib/services/catalog/catalog_mcp_handler.dart`
- `client/lib/services/catalog/catalog_mcp_transport.dart`
- `client/lib/services/catalog/modules/skill_catalog_module.dart`
- `client/lib/services/catalog/modules/plugin_catalog_module.dart`
- `client/lib/services/catalog/modules/mcp_catalog_module.dart`
- `client/lib/services/catalog/providers/managed_catalog_skill_provider.dart`
- `client/lib/services/catalog/providers/catalog_prompt_provider.dart`
- `client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md`

Modify:

- `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart` — route `/catalog/mcp` before TeamBus register check; expose `catalogMcpEndpoint`
- `client/lib/repositories/session_repository.dart` — public `findById`
- `client/lib/services/launch/session_shell_connector.dart` — merge catalog extra MCP on simple and team connects
- `client/lib/services/provider/config_profile_service.dart` — managed skill provider in `_catalogResourceProviders`
- `client/lib/services/resource/resource_resolver.dart` — same managed skill provider
- `client/lib/services/session/member_role_provision.dart` — catalog read allows on all Claude/flashskyai launches
- `client/lib/services/cli/cursor/provider/cursor_cli_config_policy.dart` — catalog read allows (simple + mixed)
- `client/lib/app/app_shell.dart` — construct registry/handler/bus, attach gateway, cubit listeners
- Claude/flashskyai/cursor permission merge call sites as listed in Task 9

---

### Task 1: Catalog core types, registry, policy, mutation bus

**Files:**
- Create: `client/lib/services/catalog/catalog_mcp_constants.dart`
- Create: `client/lib/services/catalog/catalog_kind.dart`
- Create: `client/lib/services/catalog/catalog_kind_registry.dart`
- Create: `client/lib/services/catalog/catalog_mcp_policy.dart`
- Create: `client/lib/services/catalog/catalog_mutation_bus.dart`
- Test: `client/test/services/catalog/catalog_kind_registry_test.dart`

**Interfaces:**
- Produces:
  - `const catalogMcpServerName = 'teampilot'`
  - `const catalogMcpPath = '/catalog/mcp'`
  - `enum CatalogOp { search, list, read, install, importPath, create, update, unbind, delete }`
  - `enum CatalogBindTo { workspace }`
  - `class CatalogException implements Exception`
  - `class CatalogRequest`
  - `class CatalogResult`
  - `class CatalogToolSpec { name, description, inputSchema, mutating }`
  - `abstract interface class CatalogKindModule`
  - `class CatalogKindRegistry { register, module, allTools, dispatch, listInstalled }`
  - `abstract final class CatalogMcpPolicy { readToolNames, mutateToolNames, claudeAllowEntries, cursorAllowEntries }`
  - `class CatalogMutationEvent { kind, op, ids, workspaceId }`
  - `class CatalogMutationBus { emit, listen }`

- [ ] **Step 1: Write the failing test**

`client/test/services/catalog/catalog_kind_registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_kind_registry.dart';
import 'package:teampilot/services/catalog/catalog_mcp_policy.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

class _FakeModule implements CatalogKindModule {
  _FakeModule({required this.kind, this.supportsCreate = true});

  @override
  final String kind;
  @override
  final bool supportsCreate;
  @override
  bool get supportsImport => true;
  @override
  bool get supportsInstall => true;

  @override
  List<CatalogToolSpec> advertise() => [
    CatalogToolSpec(
      name: 'search_$kind',
      description: 'Search $kind',
      inputSchema: const {'type': 'object', 'properties': {}},
      mutating: false,
    ),
    if (supportsCreate)
      CatalogToolSpec(
        name: 'create_$kind',
        description: 'Create $kind',
        inputSchema: const {'type': 'object', 'properties': {}},
        mutating: true,
      ),
  ];

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) async {
    if (op == CatalogOp.create && !supportsCreate) {
      throw CatalogException('unsupported_op', 'no create');
    }
    return CatalogResult.ok(
      kind: kind,
      ids: const ['x'],
      workspaceId: req.workspaceId,
    );
  }
}

void main() {
  final fs = LocalFilesystem();
  CatalogRequest req() => CatalogRequest(
    sessionId: 's',
    workspaceId: 'w',
    arguments: const {},
    workFs: fs,
    allowedRoots: const ['/work'],
  );

  test('omits create_plugin when supportsCreate is false', () {
    final registry = CatalogKindRegistry()
      ..register(_FakeModule(kind: 'skill'))
      ..register(_FakeModule(kind: 'plugin', supportsCreate: false));
    final names = registry.allTools().map((t) => t.name).toList();
    expect(names, contains('list_installed'));
    expect(names, contains('search_skill'));
    expect(names, contains('create_skill'));
    expect(names, contains('search_plugin'));
    expect(names, isNot(contains('create_plugin')));
  });

  test('policy splits read and mutate tools', () {
    final registry = CatalogKindRegistry()
      ..register(_FakeModule(kind: 'skill'));
    expect(CatalogMcpPolicy.readToolNames(registry), contains('search_skill'));
    expect(CatalogMcpPolicy.readToolNames(registry), contains('list_installed'));
    expect(
      CatalogMcpPolicy.mutateToolNames(registry),
      contains('create_skill'),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      contains('mcp__teampilot__search_skill'),
    );
    expect(
      CatalogMcpPolicy.cursorAllowEntries(registry),
      contains('Mcp(teampilot:search_skill)'),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      isNot(contains('mcp__teampilot__create_skill')),
    );
  });

  test('dispatch routes install_skill to skill module install op', () async {
    final registry = CatalogKindRegistry()..register(_FakeModule(kind: 'skill'));
    final result = await registry.dispatch('create_skill', req());
    expect(result.ids, ['x']);
    expect(result.restartRequired, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/catalog/catalog_kind_registry_test.dart`

Expected: FAIL compiling (library not found)

- [ ] **Step 3: Write implementation**

`catalog_mcp_constants.dart`:

```dart
const catalogMcpServerName = 'teampilot';
const catalogMcpPath = '/catalog/mcp';
```

`catalog_kind.dart` — include `CatalogOp`, `CatalogBindTo.workspace`, `CatalogException(code, message, {details})`, `CatalogFailure(path, code, message)`, `CatalogRequest` (fields: sessionId, workspaceId, memberId, bindTo default workspace, overwrite default false, arguments, workFs, allowedRoots), `CatalogResult.ok` / `CatalogResult.partial` with `restartRequired: true` on all write-shaped results, `CatalogToolSpec`, `CatalogKindModule`.

`CatalogKindRegistry.dispatch(String toolName, CatalogRequest req)`:

- `list_installed` → iterate modules `handle(CatalogOp.list, req)` and merge `data`
- parse `<op>_<kind>` where op maps `search|read|install|import|create|update|unbind|delete` (`import` → `CatalogOp.importPath`)
- unknown tool → `CatalogException('unsupported_op', ...)`
- missing module → same

`CatalogMcpPolicy`: read = tools with `mutating: false`; mutate = `mutating: true`; Claude entries `mcp__teampilot__$name`; Cursor `Mcp(teampilot:$name)`.

`CatalogMutationBus`: in-memory `StreamController<CatalogMutationEvent>.broadcast()`.

Default `list_installed` tool spec (mutating false) is owned by the registry, not a kind module.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/catalog/catalog_kind_registry_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/catalog_mcp_constants.dart \
  client/lib/services/catalog/catalog_kind.dart \
  client/lib/services/catalog/catalog_kind_registry.dart \
  client/lib/services/catalog/catalog_mcp_policy.dart \
  client/lib/services/catalog/catalog_mutation_bus.dart \
  client/test/services/catalog/catalog_kind_registry_test.dart
git commit -m "$(cat <<'EOF'
feat: add catalog kind registry and MCP tool policy

EOF
)"
```

---

### Task 2: Path sandbox + workspace binder

**Files:**
- Create: `client/lib/services/catalog/catalog_path_sandbox.dart`
- Create: `client/lib/services/catalog/catalog_workspace_binder.dart`
- Test: `client/test/services/catalog/catalog_path_sandbox_test.dart`
- Test: `client/test/services/catalog/catalog_workspace_binder_test.dart`

**Interfaces:**
- Consumes: `CatalogException`, `CatalogBindTo`
- Produces:
  - `void assertSafeImportPath({required Filesystem fs, required String path, required List<String> allowedRoots})`
  - `class CatalogWorkspaceBinder { Future<void> bindIds({required String workspaceId, required CatalogBindTo bindTo, required void Function(ConfigBundle current) apply}); Future<void> unbindIds(...) }`

- [ ] **Step 1: Write failing tests**

`catalog_path_sandbox_test.dart`: temp dir as allowed root; `join(root, 'skills/foo')` succeeds; `/etc/passwd` and a symlink escaping the root throw `unsafe_path`.

`catalog_workspace_binder_test.dart`: `AppStorage.installForTesting`; bind `skillIds: ['a']`; load `WorkspaceProjectConfigRepository` and expect `bundle.skillIds == ['a']`; second bind of `a` stays one entry; `bindTo` other than workspace throws `bind_scope_unsupported`; unbind removes the id.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/catalog/catalog_path_sandbox_test.dart test/services/catalog/catalog_workspace_binder_test.dart`

Expected: FAIL (libraries missing)

- [ ] **Step 3: Implement**

Sandbox: normalize with `fs.pathContext.normalize`; require `path` equals an allowed root or is a descendant (`$root/` prefix after normalize); `readSymlinkTarget` if present must also stay inside some allowed root.

Binder: `CatalogBindTo.workspace` only; `repo.updateBundle` adding ids with a `LinkedHashSet` so order is stable and duplicates collapse. Unbind filters the matching id list (`skillIds` / `pluginIds` / `mcpServerIds` chosen by caller via `apply`).

- [ ] **Step 4: Run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/catalog_path_sandbox.dart \
  client/lib/services/catalog/catalog_workspace_binder.dart \
  client/test/services/catalog/catalog_path_sandbox_test.dart \
  client/test/services/catalog/catalog_workspace_binder_test.dart
git commit -m "$(cat <<'EOF'
feat: add catalog import path sandbox and workspace binder

EOF
)"
```

---

### Task 3: Skill catalog module

**Files:**
- Create: `client/lib/services/catalog/modules/skill_catalog_module.dart`
- Test: `client/test/services/catalog/skill_catalog_module_test.dart`

**Interfaces:**
- Consumes: `CatalogKindModule`, `CatalogWorkspaceBinder`, `CatalogMutationBus`, `assertSafeImportPath`, `SkillRepository`, `SkillAcquisitionEngine`, `SkillInstallService.installLocal`
- Produces: `class SkillCatalogModule implements CatalogKindModule` with `kind == 'skill'`, `supportsCreate == true`

Advertise: `search_skill` wait — spec tools are `search_skills` (plural). **Use spec names:** `search_skills`, `read_skill`, `install_skill`, `import_skill`, `create_skill`, `update_skill`, `unbind_skill`, `delete_skill`. Registry dispatch must parse these irregular names.

Update `CatalogKindRegistry.dispatch` in this task: map exact tool names from `advertise()`, do not naively split on last underscore only. Keep a `Map<String, ({String kind, CatalogOp op})>` built from advertised tools plus `list_installed`.

- [ ] **Step 1: Write failing tests**

Cover:

1. `create_skill` with `name`, `directory`, `body` writes `skills/installed/<dir>/SKILL.md`, manifest id `local:<dir>`, binds workspace, emits bus event, `restartRequired == true`
2. `import_skill` of a temp dir containing `SKILL.md` copies into `skills/installed` and binds
3. `import_skill` path outside `allowedRoots` → `unsafe_path`
4. `import_skill` with no SKILL.md → `no_skill_md`
5. `delete_skill` removes manifest row and unbinds
6. `install_skill` when id already installed only binds (idempotent)
7. `advertise()` has no unexpected names

Use `AppStorage.installForTesting` + real `SkillRepository` / `SkillInstallService` like `skill_install_service_test.dart`. Fake `SkillAcquisitionEngine` is not needed for create/import.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/catalog/skill_catalog_module_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement SkillCatalogModule**

`handle`:

- `search`: call injected `Future<List<Map<String, Object?>>> Function(String query) search` (in app_shell wire to SkillCubit's registry search later; for tests inject a lambda). If search not injected, return empty list.
- `list`: `repository.loadInstalled()` plus bound ids from workspace config
- `read`: load SKILL.md text + relative files
- `install`: `SkillDependencyRef` / `installFromDiscovery` via injected engine or repository; if already in manifest, skip file install; then bind
- `importPath`: `assertSafeImportPath`; discover SKILL.md at path, one-level children, or `path/skills/*`; copy tree into `skills/installed/<basename>` via `installLocal(overwrite: req.overwrite)`; partial failures use `CatalogResult.partial`
- `create`: require `name` + `body`; directory default from name slug; `installLocal`
- `update`: overwrite files for existing id
- `unbind`: binder only
- `delete`: `repository.uninstall` then unbind (uninstall callbacks for teams are wired in Task 11 via existing SkillCubit `onSkillUninstalled` when cubit reloads; module itself should call the same `SkillRepository.uninstall` the UI uses)

After successful write ops: `bus.emit(CatalogMutationEvent(kind: 'skill', op: op, ids: ids, workspaceId: req.workspaceId))`.

Fix registry dispatch to use advertised names (plural `search_skills`). Update Task 1 tests if they used `search_skill`.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/catalog/catalog_kind_registry_test.dart test/services/catalog/skill_catalog_module_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/catalog_kind_registry.dart \
  client/lib/services/catalog/modules/skill_catalog_module.dart \
  client/test/services/catalog/skill_catalog_module_test.dart \
  client/test/services/catalog/catalog_kind_registry_test.dart
git commit -m "$(cat <<'EOF'
feat: add skill catalog module for agent install and import

EOF
)"
```

---

### Task 4: Plugin catalog module

**Files:**
- Create: `client/lib/services/catalog/modules/plugin_catalog_module.dart`
- Test: `client/test/services/catalog/plugin_catalog_module_test.dart`

**Interfaces:**
- Consumes: `PluginRepository` / `PluginInstallService.installFromDirectory`, binder, bus, sandbox
- Produces: `PluginCatalogModule` with `supportsCreate == false`

- [ ] **Step 1: Write failing tests**

1. `advertise()` contains `install_plugin`, `import_plugin`, `delete_plugin`; does **not** contain `create_plugin`
2. `import_plugin` of a dir with `plugin.json` (minimal `{ "name": "demo" }` matching what `PluginInstallService.installFromDirectory` already accepts) installs and binds `pluginIds`
3. Importing a skill-only dir (only `SKILL.md`) throws `wrong_kind`
4. `handle(CatalogOp.create, ...)` throws `unsupported_op`

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/catalog/plugin_catalog_module_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement**

Detect plugin layout: `plugin.json` or `.claude-plugin/plugin.json`. Copy/install via `PluginInstallService.installFromDirectory`. Bind `pluginIds`. `update` → `updatePlugin` / `updateInPlace` as the install service already does. `delete` → repository uninstall + unbind.

- [ ] **Step 4: Run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/modules/plugin_catalog_module.dart \
  client/test/services/catalog/plugin_catalog_module_test.dart
git commit -m "$(cat <<'EOF'
feat: add plugin catalog module without create_plugin

EOF
)"
```

---

### Task 5: MCP catalog module

**Files:**
- Create: `client/lib/services/catalog/modules/mcp_catalog_module.dart`
- Test: `client/test/services/catalog/mcp_catalog_module_test.dart`

**Interfaces:**
- Consumes: `McpRepository`, `McpListingInstallService`, binder, bus, sandbox
- Produces: `McpCatalogModule`

- [ ] **Step 1: Write failing tests**

1. `create_mcp` upserts a stdio spec `{name, command, args}` and binds `mcpServerIds`
2. `read_mcp` returns spec with env values replaced by `***` (keys remain)
3. `import_mcp` reads a `.mcp.json` under allowedRoots with `mcpServers.docs = {type:http, url:...}` and upserts
4. `install_mcp` with injected listing draft function returns that id and binds

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/catalog/mcp_catalog_module_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement**

`create` / `update` / `install` go through `McpRepository.upsert`. `read` redacts string values under `env` and `headers`. `importPath` parses JSON object or `{mcpServers: {...}}`. `delete` uses repository delete + unbind.

- [ ] **Step 4: Run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/modules/mcp_catalog_module.dart \
  client/test/services/catalog/mcp_catalog_module_test.dart
git commit -m "$(cat <<'EOF'
feat: add MCP catalog module with secret-redacted reads

EOF
)"
```

---

### Task 6: Catalog MCP JSON-RPC handler

**Files:**
- Create: `client/lib/services/catalog/catalog_mcp_handler.dart`
- Test: `client/test/services/catalog/catalog_mcp_handler_test.dart`

**Interfaces:**
- Consumes: `CatalogKindRegistry`, `JsonRpcRequest`, `McpToolResponse`, `McpMethod`
- Produces: `class CatalogMcpHandler { static const serverName = 'teampilot'; Future<JsonRpcResponse?> handle(JsonRpcRequest req, CatalogMcpSession session); }`
- `class CatalogMcpSession { sessionId, workspaceId, memberId, workFs, allowedRoots }`

- [ ] **Step 1: Write failing test**

Using the fake module from Task 1 (move fake to `test/services/catalog/support/fake_catalog_module.dart` if it keeps files small):

1. `initialize` returns protocol `2025-06-18` and `serverInfo.name == 'teampilot'`
2. `tools/list` includes `list_installed` and advertised tools
3. `tools/call` `create_skill` returns `isError: false` text containing `restart_required`
4. `CatalogException` becomes `McpToolResponse.toolError` whose text includes `code=unsupported_op`
5. Missing session workspace (handler constructed without session) — tested in Task 7; here assume session is present
6. Unknown method → JSON-RPC error (not HTTP)

Encode results as JSON text in the MCP content so agents can parse `ok`, `ids`, `restart_required`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/catalog/catalog_mcp_handler_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement handler**

Mirror `TeammateBusMcpHandler` initialize / tools/list / tools/call / notifications (return null). `tools/call` builds `CatalogRequest` from `CatalogMcpSession` + arguments (`bind_to` parsed to enum; invalid → `bind_scope_unsupported`). Catch `CatalogException` → `toolError`.

- [ ] **Step 4: Run tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/catalog_mcp_handler.dart \
  client/test/services/catalog/catalog_mcp_handler_test.dart \
  client/test/services/catalog/support/fake_catalog_module.dart
git commit -m "$(cat <<'EOF'
feat: add teampilot catalog MCP JSON-RPC handler

EOF
)"
```

---

### Task 7: Gateway `/catalog/mcp` + session lookup

**Files:**
- Modify: `client/lib/repositories/session_repository.dart` — add `Future<AppSession?> findById(String sessionId)` wrapping `_findSession`
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Test: `client/test/services/catalog/catalog_mcp_gateway_test.dart`
- Test: add a unit test for `findById` in existing session repository test file if one exists; otherwise `client/test/repositories/session_repository_find_by_id_test.dart`

**Interfaces:**
- Consumes: `CatalogMcpHandler`, `catalogMcpPath`
- Produces: `TeammateBusMcpGateway.catalogMcpEndpoint`, `attachCatalogHandler(CatalogMcpHandler handler, {required Future<CatalogMcpSession?> Function(String sessionId) resolveSession})`

- [ ] **Step 1: Write failing tests**

Gateway test: `ensureStarted()`, POST JSON-RPC `tools/list` to `catalogMcpEndpoint` with `X-Session: sess-1` while **no** `register()` TeamBus session exists. Stub `resolveSession` returning a `CatalogMcpSession`. Expect 200 and tool list.

Second case: missing `X-Session` still returns HTTP 200 with JSON-RPC/tool error (not 400), so Claude Stop hooks do not loop.

Third case: existing `/mcp` TeamBus register path still 400 without register (regression).

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL (no catalog route)

- [ ] **Step 3: Implement**

In `_onRequest`, handle `POST && path == catalogMcpPath` **before** the `_delegates[sessionId] == null` bail-out. Resolve session via callback; on failure write JSON-RPC error in 200 body. Attach handler fields on the gateway.

`SessionRepository.findById` public.

- [ ] **Step 4: Run tests**

Also run: `cd client && flutter test test/services/team_bus/idle_notification_test.dart`

Expected: PASS (bus regression)

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart \
  client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart \
  client/test/services/catalog/catalog_mcp_gateway_test.dart \
  client/test/repositories/session_repository_find_by_id_test.dart
git commit -m "$(cat <<'EOF'
feat: serve catalog MCP on loopback without TeamBus registration

EOF
)"
```

---

### Task 8: Transport + extra MCP injection on every connect

**Files:**
- Create: `client/lib/services/catalog/catalog_mcp_transport.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Test: `client/test/services/catalog/catalog_mcp_transport_test.dart`
- Modify existing simple/team connect tests that snapshot extra MCP servers (search `extraMcpServers` / `teammate-bus` in `client/test/services/launch` and `client/test/services/provider`) so they still pass and now expect `teampilot`

**Interfaces:**
- Produces: `Map<String, Object?> resolveCatalogMcpTransportConfig({required CliToolRegistry cliRegistry, required Uri catalogEndpoint, required String sessionId, required String memberId, required CliTool cli, RemoteBusBinding? remoteBinding})`

Rules (locked):

1. If `remoteBinding != null` → HTTP `http://127.0.0.1:${remoteBinding.idleHttpTunnelPort}/catalog/mcp` with `X-Session`, `X-Member`, `X-Bus-Token`
2. Else if local stdio bridge supported (same flags as bus: `supportsLocalStdioBridge` + native backend + `BusBridgeLocator.resolve()`) → `teammateBusMcpServerConfigStdio` but `endpoint` is `catalogEndpoint` (bridge `--bus-url` is the full catalog URL)
3. Else HTTP `catalogEndpoint` with `X-Session` / `X-Member`

- [ ] **Step 1: Write failing transport tests**

Local HTTP fallback when bridge is null. Local stdio when fake `supportsLocalStdioBridge` and a bridge path is passed in (inject locator via optional parameter `String? Function()? bridgeLocator` defaulting to `BusBridgeLocator.resolve`). Remote uses idle HTTP port + `/catalog/mcp` + token, never the raw relay argv.

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL

- [ ] **Step 3: Implement transport + merge into connect**

Add `withCatalogMcpServer` in `catalog_mcp_transport.dart`:

```dart
Map<String, Map<String, Object?>> withCatalogMcpServer({
  required Map<String, Map<String, Object?>> extra,
  required Map<String, Object?> catalogConfig,
}) {
  return {...extra, catalogMcpServerName: catalogConfig};
}
```

In `session_shell_connector.dart` simple `prepareSimpleConnect` and team `prepareTeamConnect`, set `extraMcpServers: withCatalogMcpServer(extra: existingOrEmpty, catalogConfig: resolveCatalogMcpTransportConfig(...))`. For simple, `memberId` is `session.sessionId`. For team, keep existing teammate-bus map as `existing`. Remote simple: pass the same remote HTTP binding used for agent-status when non-null.

If simple SSH currently has no idle tunnel, use the agent-status resolver's HTTP port when present; if both are null, local HTTP config is acceptable only for native local PTY.

- [ ] **Step 4: Run tests**

Run transport tests plus any updated launch tests.

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/catalog_mcp_transport.dart \
  client/lib/services/launch/session_shell_connector.dart \
  client/test/services/catalog/catalog_mcp_transport_test.dart
git commit -m "$(cat <<'EOF'
feat: inject teampilot catalog MCP into every session connect

EOF
)"
```

---

### Task 9: Pre-allow read tools only

**Files:**
- Modify: `client/lib/services/session/member_role_provision.dart`
- Modify: `client/lib/services/cli/claude/capabilities/provider.dart` (call site of `applyTeamSessionPolicy`)
- Modify: `client/lib/services/cli/flashskyai/capabilities/provider.dart`
- Modify: `client/lib/services/cli/cursor/provider/cursor_cli_config_policy.dart`
- Modify: cursor overlay merge so simple sessions also get catalog read allows (find `applyMixedTeamSessionPolicy` call sites; add `applyCatalogReadPolicy` used for mixed **and** simple)
- Test: `client/test/services/session/member_role_provision_test.dart`
- Test: `client/test/services/provider/cursor/cursor_cli_config_policy_test.dart` (create if missing)

**Interfaces:**
- Consumes: `CatalogMcpPolicy.claudeAllowEntries` / `cursorAllowEntries`
- `MemberRoleProvision.applyCatalogReadAllows(settings, {required List<String> claudeEntries})` merges into `permissions.allow` for **every** launch (not only mixed)
- Cursor: `CursorCliConfigPolicy.catalogReadAllowEntries(List<String> cursorEntries)` merged in both mixed and simple home provision

Do **not** add `mcp__teampilot` wildcard. Do **not** add mutate tool names.

- [ ] **Step 1: Write failing tests**

`applyCatalogReadAllows` on `{}` contains `mcp__teampilot__search_skills` and `mcp__teampilot__list_installed`, does not contain `mcp__teampilot__install_skill`. `applyTeamSessionPolicy(mixed: true)` still contains `mcp__teammate-bus`. Cursor policy contains `Mcp(teampilot:search_skills)` and not `Mcp(teampilot:install_skill)`.

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL

- [ ] **Step 3: Implement merges at Claude, flashskyai, and cursor settings writers**

Pass entries from `CatalogMcpPolicy` using the live registry. To avoid a circular import, `applyCatalogReadAllows` takes the already-built string list.

If Codex/OpenCode have an MCP allow list analogous to Claude, add the same read entries there in this task; if they auto-allow all MCP tools, document that in a comment on `CatalogMcpPolicy` and do not invent a new allow file.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/session/member_role_provision_test.dart test/services/cli/claude/`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/member_role_provision.dart \
  client/lib/services/cli/claude/capabilities/provider.dart \
  client/lib/services/cli/flashskyai/capabilities/provider.dart \
  client/lib/services/cli/cursor/provider/cursor_cli_config_policy.dart \
  client/test/services/session/member_role_provision_test.dart
git commit -m "$(cat <<'EOF'
feat: pre-allow catalog MCP read tools only

EOF
)"
```

---

### Task 10: Managed skill + prompt providers

**Files:**
- Create: `client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md`
- Create: `client/lib/services/catalog/providers/managed_catalog_skill_provider.dart`
- Create: `client/lib/services/catalog/providers/catalog_prompt_provider.dart`
- Modify: `client/lib/services/provider/config_profile_service.dart` `_catalogResourceProviders`
- Modify: `client/lib/services/resource/resource_resolver.dart` `assemble` providers list
- Modify: prompt provision call in `cli_resource_provisioner.dart` / config_profile to append `CatalogPromptProvider` to prompt providers (inject via `ResourceProviderSet` if it already has a prompts list; if not, add `prompts` to that set **only if** the set already supports it — `ResourceProviderSet` already has `prompts` in tests)
- Test: `client/test/services/catalog/managed_catalog_skill_provider_test.dart`
- Test: `client/test/services/resource/resource_resolver_test.dart` (extend) or new test asserting `teampilot-catalog` appears even when `scope.skillIds` is empty

**Interfaces:**
- `ManagedCatalogSkillProvider.providerId == 'teampilot-catalog'`
- origin `ResourceOriginKind.managed`
- artifact directory is the resolved path of the shipped SKILL.md parent; in tests pass an explicit `sourceDirectory`
- invocation name `teampilot-catalog`
- `CatalogPromptProvider` appends one sentence: `To install or manage TeamPilot skills, plugins, or MCP servers, load the teampilot-catalog skill and use the teampilot MCP. Do not install into ~/.claude.`

SKILL.md frontmatter description (must match spec trigger wording). Body: numbered workflow — search first, `install_*` vs `import_*`, create/update/unbind/delete, reconnect, never write `~/.claude`.

- [ ] **Step 1: Write failing tests**

Provider `provide` returns one contribution with id `teampilot-catalog` regardless of `scope.skillIds`. Resolver/assembler with empty skill ids still includes that contribution when the managed provider is in the list. Prompt provider content contains `teampilot-catalog` and `teampilot` MCP.

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL

- [ ] **Step 3: Implement files + wire `_catalogResourceProviders` and `ResourceResolver.assemble`**

Always insert `ManagedCatalogSkillProvider()` first in the skills provider list so it cannot be dropped when catalog ids are empty.

Wire `CatalogPromptProvider` into the prompt provider list used by `CliResourceProvisioner` / `PromptHubService` (config_profile extra providers). If extra prompt providers are currently only CLI-registry providers, add an injected list on `ResourceProviderSet.prompts` at the same place hooks already get managed providers.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/catalog/managed_catalog_skill_provider_test.dart test/services/resource/resource_resolver_test.dart test/services/resource/cli_resource_provisioner_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/catalog/managed_skills \
  client/lib/services/catalog/providers \
  client/lib/services/provider/config_profile_service.dart \
  client/lib/services/resource/resource_resolver.dart \
  client/test/services/catalog/managed_catalog_skill_provider_test.dart
git commit -m "$(cat <<'EOF'
feat: always provision teampilot-catalog skill and one-line prompt

EOF
)"
```

---

### Task 11: App shell wiring + cubit refresh

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/catalog/catalog_mutation_bus_test.dart` (bus already exists; add listen/emit test if not in Task 1)
- Optional widget/bootstrap test only if there is an existing app_shell test harness; do not create a full app test

**Interfaces:**
- `app_shell` constructs `CatalogMutationBus`, `CatalogWorkspaceBinder`, three modules, `CatalogKindRegistry`, `CatalogMcpHandler`
- `teammateBusMcpGateway.attachCatalogHandler(handler, resolveSession: ...)`
- `resolveSession` uses `sessionRepository.findById`, folder paths from the session as `allowedRoots`, `AppStorage.fs` for local / work filesystem from the session launch target when already available; if work fs is not cheap to resolve at MCP-call time, use `AppStorage.fs` for local and `RuntimeContextRegistry` work fs for ssh/wsl (same resolver launch uses)
- Subscribe: `bus.listen` → `skillCubit.loadAll()`, `pluginCubit.loadAll()` (or existing reload method), `mcpCubit.loadAll()`, `workspaceProjectConfigCubit` reload for `event.workspaceId`

- [ ] **Step 1: Write failing test for bus → callback**

Direct unit test: emit event, verify a recording listener is invoked with the same ids. Wiring in app_shell is covered by constructing the registry in a small `catalog_runtime_test.dart` that builds modules with test `AppStorage` and round-trips `create_skill` then `list_installed`.

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL until app_shell exports a `CatalogRuntime` factory usable by tests

- [ ] **Step 3: Extract `CatalogRuntime.assemble(...)` in `client/lib/services/catalog/catalog_runtime.dart`**

Keeps `app_shell` thin: `final catalogRuntime = CatalogRuntime.assemble(...)`; gateway attach; cubit subscriptions. Tests use `CatalogRuntime.assemble` without Flutter widgets.

- [ ] **Step 4: Run catalog tests + `flutter analyze --no-fatal-infos --no-fatal-warnings`**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart \
  client/lib/services/catalog/catalog_runtime.dart \
  client/test/services/catalog/catalog_runtime_test.dart \
  client/test/services/catalog/catalog_mutation_bus_test.dart
git commit -m "$(cat <<'EOF'
feat: wire catalog MCP runtime into app shell

EOF
)"
```

---

### Task 12: Spec/docs closeout

**Files:**
- Modify: `docs/superpowers/specs/2026-08-19-teampilot-catalog-mcp-design.md` status already Approved
- Modify: `docs/cli-architecture.md` — one short subsection that launch injects a managed `teampilot` MCP + `teampilot-catalog` skill; kinds stay in `services/catalog/`
- Modify: `AGENTS.md` table “Where to change code” — add Catalog MCP row pointing at `client/lib/services/catalog/`

**Interfaces:** none

- [x] **Step 1: Add the AGENTS.md / cli-architecture.md paragraphs** (no TBD)

- [x] **Step 2: Run `cd client && flutter test test/services/catalog test/services/team_bus/idle_notification_test.dart test/services/resource/resource_resolver_test.dart --exclude-tags integration`**

Expected: PASS

- [x] **Step 3: Commit**

```bash
git add AGENTS.md docs/cli-architecture.md \
  docs/superpowers/specs/2026-08-19-teampilot-catalog-mcp-design.md \
  docs/superpowers/plans/2026-08-19-teampilot-catalog-mcp.md
git commit -m "$(cat <<'EOF'
docs: document TeamPilot catalog MCP for agents

EOF
)"
```

---

## Spec coverage (self-review)

| Spec item | Task |
|---|---|
| Kind modules + generated tools, no `create_plugin` | 1, 3, 4 |
| `list_installed` shared | 1 |
| Workspace bind + `bind_to` | 2 |
| Skill install/import/create/update/unbind/delete | 3 |
| Plugin import/install/delete | 4 |
| MCP create/import/read redaction | 5 |
| JSON-RPC handler, `restart_required` | 6 |
| `/catalog/mcp` without TeamBus | 7 |
| Inject every session; stdio bridge via catalog URL; SSH via idle HTTP tunnel | 8 |
| Read tools pre-allowed, mutate not | 9 |
| Managed skill trigger + one-line prompt | 10 |
| Mutation bus → cubits, no cubit-from-module | 2, 3, 11 |
| Partial import failures | 3 |
| Path sandbox | 2, 3 |
| Docs | 12 |

No remaining spec requirement without a task. Tool names in Task 3 override the naive `search_$kind` fake from Task 1 so they match the spec (`search_skills`).

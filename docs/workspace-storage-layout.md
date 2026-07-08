# Workspace storage layout

Canonical on-disk layout under **`<teampilotRoot>`** (`AppPaths.basePath` / `AppStorage.appDataRoot`). Code: `WorkspaceLayout`, `RuntimeLayout`, `AppPaths`.

Typical `<teampilotRoot>` paths:

| Environment | Path |
|-------------|------|
| Linux desktop | `~/.local/share/com.hhoa.teampilot` |
| Windows native | `%APPDATA%\com.hhoa.teampilot` |
| WSL | `$HOME/.local/share/com.hhoa.teampilot` in chosen distro |
| SSH / Android | Remote host (`RemoteSshStoragePathResolver`) |

## Top-level directories

```
<teampilotRoot>/
  cli-defaults/{tool}/           # app-level CLI runtime templates
  identities-runtime/{profileId}/  # per launch-identity inherited CLI trees
    session-counter.json         # monotonic cliTeamName allocator
    {tool}/
    mcp/servers.json
  launch-profiles/{id}/profile.json
  launch-profiles-index.json     # derived snapshot for fast startup
  workspace/
    workspaces-index.json
    workspaces/{workspaceId}/      # see below
  providers/{tool}/providers.json  # per-CLI provider catalog
  skills/installed/              # global skill library
  plugins/installed/             # global plugin library
  mcp/mcp_servers.json           # global MCP catalog
  extensions/state.json
  automations/catalog.json       # global automation sidebar index
  cli-presets.json
  ssh_profiles/
  targets.json                   # runtime targets registry (local / WSL / SSH)
  team-hub/                      # TeamHub cache + registries
  worktrees/{repoName}/{branch}/ # app-managed git worktrees
  ui/                            # home workspace UI prefs (tabs, favorites, …)
  notifications.json
```

## Workspace directory

Each workspace is self-contained; deleting `workspace/workspaces/{workspaceId}/` removes manifest, bindings, sessions (metadata + bus + CLI runtime).

```
workspace/workspaces/{workspaceId}/
  manifest.json                  # Workspace (folders, defaultProfileId, session ids, …)
  project-config.json            # workspace-scoped skill/plugin/mcp/extension bindings
  profile.json                   # optional embedded PersonalProfile (legacy / migration)
  assets/icon.*                  # custom workspace icon
  config/                        # workspace-level CLI overrides (inherits app → identity)
    mcp/servers.json
    {tool}/plugins/
  automations/
    {launchProfileId}.json       # automation rules + run history for one tab scope
  sessions/{sessionId}/
    session.json
    bus/mail/{memberId}.jsonl
    bus/tasks/tasks.jsonl
    runtime/{tool}/                # personal / native single-agent CONFIG_DIR
    runtime/{memberId}/{tool}/     # mixed-mode per-member CONFIG_DIR
    runtime/_shared/{tool}/        # session-level shared CLI state (e.g. cursor warm tier)
```

## CLI config inheritance

At launch, `RuntimeLayout` links each layer into the session runtime tree (PTY `CONFIG_DIR`):

1. **App** — `cli-defaults/{tool}/`
2. **Identity** — `identities-runtime/{profileId}/{tool}/` (launch profile id)
3. **Workspace** — `workspace/workspaces/{workspaceId}/config/{tool}/`
4. **Session** — `workspace/workspaces/{workspaceId}/sessions/{sessionId}/runtime/…`

`SessionLifecycleService` performs provisioning and per-CLI writers; see `runtime_layout.dart` and `session_lifecycle_service.dart`.

## Launch profiles

Reusable launch identities (personal or team) live outside any workspace:

```
launch-profiles/{profileId}/profile.json
```

`LaunchProfileRepository` is source of truth; `launch-profiles-index.json` is a derived startup snapshot.

## Related docs

- [AGENTS.md](../AGENTS.md) — architecture overview for AI assistants
- [README.md](../README.md) — user-facing feature descriptions

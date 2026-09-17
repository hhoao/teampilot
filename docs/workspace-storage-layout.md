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
  identities-runtime/{profileId}/  # per **team** launch-identity inherited CLI trees
    session-counter.json         # monotonic cliTeamName allocator
    {tool}/
    mcp/servers.json
  launch-profiles/{id}/profile.json  # TeamProfile documents only
  launch-profiles-index.json     # derived snapshot for fast startup
  workspace/
    cache/cli/{tool}/{providerKey}/  # CLI runtime cache (global; `_shared` if no provider)
    workspaces-index.json
    workspaces/{workspaceId}/      # see below
  providers/{tool}/providers.json  # per-CLI provider catalog
  skills/installed/              # global skill library (git-dir or script acquire)
  plugins/installed/             # global plugin library
  mcp/mcp_servers.json           # global MCP catalog
  extensions/state.json
  automations/catalog.json       # global automation sidebar index
  cli-presets.json
  ssh_profiles/
  targets.json                   # runtime targets registry (local / WSL / SSH)
  team-hub/                      # Team Hub template registry + cache
  member-hub/                    # Expert Hub catalog UX state + local templates
  hub-publish/                   # Hub publish credentials metadata + PR badge records
  worktrees/{repoName}/{branch}/ # app-managed git worktrees
  ui/                            # home workspace UI prefs (tabs, favorites, …)
  notifications.json
  event-transport.json           # loopback Event Transport advertisement (desktop server)
```

## Workspace directory

Each workspace is self-contained; deleting `workspace/workspaces/{workspaceId}/` removes manifest, bindings, sessions (metadata + bus + CLI runtime).

```
workspace/workspaces/{workspaceId}/
  manifest.json                  # Workspace (folders, defaultProfileId, session ids, …)
  project-config.json            # workspace-scoped skill/plugin/mcp/extension bindings
  session-groups.json            # manual sidebar session groups
  sessions-index.json            # derived sidebar snapshot (source remains session.json)
  workbench-layout.json          # workbench split-layout snapshot (center + floating groups)
  assets/icon.*                  # custom workspace icon
  config/                        # workspace-level CLI tree (trust + inherit cache)
    mcp/servers.json
    {tool}/                      # derived config + inherited cache children
  automations/
    simple.json                  # Simple (unteamed) automation rules + run history
    {teamProfileId}.json         # team-scoped automation rules + run history
  sessions/{sessionId}/
    session.json
    bus/mail/{memberId}.jsonl
    bus/tasks/tasks.jsonl
    runtime/{tool}/                # Simple / native single-agent CONFIG_DIR
    runtime/{memberId}/{tool}/     # mixed-mode per-member CONFIG_DIR
    runtime/_shared/{tool}/        # session-level shared CLI state (e.g. cursor warm tier)
```

## CLI config inheritance

At launch, `RuntimeLayout` links each layer into the session runtime tree (PTY `CONFIG_DIR`):

1. **App** — `cli-defaults/{tool}/`
2. **Identity** — `identities-runtime/{profileId}/{tool}/` (**team** profiles only; Simple skips)
3. **Workspace** — `workspace/workspaces/{workspaceId}/config/{tool}/`
4. **Session** — `workspace/workspaces/{workspaceId}/sessions/{sessionId}/runtime/…`

For CLI **runtime cache** (Cursor `plugins/cache` / statsig, OpenCode `node_modules`, Codex `.tmp/plugins` and `plugins/cache`):

1. **Global** — `workspace/cache/cli/{tool}/{providerKey}/` (empty dirs are created; the CLI fills them on first launch; OpenCode `npm install` writes here)
2. **Workspace** — `workspace/workspaces/{workspaceId}/config/{tool}/…` inherits the global entry (a real directory at this layer is kept as an override)
3. **Session** — `runtime/…` only `ln`s the workspace entry

This tree is **not** `~/.cursor` and **not** `cli-defaults`. `cli-defaults/{tool}/` remains app-level templates (`agents`). Cache children are not inherited from `cli-defaults`.

For `opencode`, `workspace/cache/cli/opencode/_shared/{package.json,package-lock.json,node_modules}` holds `@opencode-ai/plugin`. A one-shot migrate moves those names out of `cli-defaults/opencode/` when the cache is empty.

For `codex`, session `.tmp/plugins` and `plugins/cache` inherit `workspace/cache/cli/codex/_shared/`. Native plugin writes go through the session `CODEX_HOME` symlink into that cache. `cli-defaults/codex/.tmp` stays excluded from remote `cli-defaults` copy.

Session skills/plugins/MCP ids merge as `team > expert > workspace` via `LayeredConfigBundle` / `SessionRuntimePlan` (see [2026-07-10 expert capability pack](superpowers/specs/2026-07-10-expert-capability-pack-design.md)).

Persona prompt/playbook is **not** stored at layers 1–3; it is resolved from the expert catalog at connect and written into layer 4 via `MemberRoleProvision`.

## Team Hub (`team-hub/`)

Team **templates** — same roster shape as user teams (`roster[]` of expert keys, not embedded prompts).

Public Team Hub, Expert Hub, and Skill Pack catalogs are maintained in
[`hhoao/teampilot-resources`](https://github.com/hhoao/teampilot-resources). The
application repository tracks the same content at `resources/` as a
source-maintenance-only Git submodule; runtime consumers fetch indexed Raw
manifests and never scan the checkout.

**Git registry (resources repo):** public templates are fetched from
`https://github.com/hhoao/teampilot-resources` under the `team-hub/` subdirectory
(`index.json` + `teams/<slug>/team.json`). Catalog keys:
`hhoao/teampilot-resources/team-hub/<slug>`.

**Local app-data cache** (under `<teampilotRoot>`):

```
team-hub/cache/{owner}-{repo}/
  teams.json                     # fetched index
```

## Expert Hub (`member-hub/`)

Catalog UX and user-authored experts. Persona source-of-truth for shared experts. Spec: [Expert Hub design](superpowers/specs/2026-07-05-expert-hub-design.md).

**Git registry (resources repo):** public experts are fetched from the same
`hhoao/teampilot-resources` repo under `member-hub/` (`index.json` +
`members/<slug>/member.json`). Catalog keys:
`hhoao/teampilot-resources/member-hub/<slug>`.

**Local app-data** (under `<teampilotRoot>`):

```
member-hub/
  favorites.json                 # { "keys": ["teampilot/builtin/developer", ...] }
  recent.json                    # landing picker recents
  local-templates/{id}.json      # DiscoverableMember (user-owned experts)
  cache/{owner}-{repo}/
    members.json                 # git registry cache
```

## Hub publish (`hub-publish/`)

Local metadata for Hub upload badges (fork PR history). Spec: [My Teams / My Experts + Hub Publish](superpowers/specs/2026-07-09-my-teams-experts-and-hub-publish-design.md).

```
hub-publish/
  records.json                   # HubPublishRecord[] keyed by kind+slug (+ localId)
```

## Launch profiles

```
launch-profiles/{profileId}/profile.json
```

`LaunchProfileRepository` is source of truth; `launch-profiles-index.json` is a derived startup snapshot.

### Team profile (`TeamProfile`)

Teams persist **references** to catalog experts:

```json
{
  "kind": "team",
  "id": "my-squad",
  "name": "My Squad",
  "teamMode": "native",
  "cli": "claude",
  "skillIds": ["..."],
  "roster": [
    {
      "id": "team-lead",
      "expertKey": "teampilot/builtin/lead",
      "overrides": { "model": "opus" },
      "joinedAt": 1710000000000
    },
    {
      "id": "developer",
      "expertKey": "hhoao/teampilot-resources/member-hub/developer",
      "joinedAt": 1710000001000
    }
  ]
}
```

- `expertKey` is **required** on every slot.
- `overrides` may set provider/model/cli/effort/replicas/capabilities — **not** prompt/playbook.
- `TeamMemberConfig` exists only in memory after `materializeRosterSlot()` at connect.

### Simple launch (unteamed)

Simple mode is **not** a `PersonalProfile` / launch-identity document. Optional session-level `expertKey` selects a catalog expert capability pack; CLI preset is a dial only. Automations for Simple use fixed file `automations/simple.json`.

## Session (`session.json`)

Simple launch with expert:

```json
{
  "sessionId": "...",
  "sessionTeam": "",
  "expertKey": "teampilot/builtin/developer"
}
```

No persisted overlay blob — persona + pack deps are live-resolved from catalog at connect (same as team roster slots).

## Related docs

- [Expert capability pack design](superpowers/specs/2026-07-10-expert-capability-pack-design.md) — Simple = unteamed + expert pack; merge `team > expert > workspace`
- [Expert Hub design spec](superpowers/specs/2026-07-05-expert-hub-design.md) — teams as expert collections
- [ARCHITECTURE.md](ARCHITECTURE.md) — architecture overview (core concepts, key paths)
- [README.md](../README.md) — user-facing feature descriptions

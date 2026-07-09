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
  team-hub/                      # Team Hub template registry + cache
  member-hub/                    # Expert Hub catalog UX state + local templates
  hub-publish/                   # Hub publish credentials metadata + PR badge records
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
2. **Identity** — `identities-runtime/{profileId}/{tool}/`
3. **Workspace** — `workspace/workspaces/{workspaceId}/config/{tool}/`
4. **Session** — `workspace/workspaces/{workspaceId}/sessions/{sessionId}/runtime/…`

Persona prompt/playbook is **not** stored at layers 1–3 for teams; it is resolved from the expert catalog at connect and written into layer 4 via `MemberRoleProvision`.

## Expert Hub (`member-hub/`)

Catalog UX and user-authored experts. Persona source-of-truth for shared experts. Spec: [Expert Hub design](superpowers/specs/2026-07-05-expert-hub-design.md).

```
member-hub/
  favorites.json                 # { "keys": ["teampilot/builtin/architect", ...] }
  recent.json                    # landing picker recents
  local-templates/{id}.json      # DiscoverableMember (user-owned experts)
  cache/{owner}-{repo}/
    members.json                 # git registry cache (flashskyai/member-hub)
```

## Team Hub (`team-hub/`)

Team **templates** — same roster shape as user teams (`roster[]` of expert keys, not embedded prompts):

```
team-hub/cache/{owner}-{repo}/
  teams.json                     # fetched index
teams/{slug}/team.json           # DiscoverableTeam with roster[]
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
      "expertKey": "flashskyai/member-hub/developer",
      "joinedAt": 1710000001000
    }
  ]
}
```

- `expertKey` is **required** on every slot.
- `overrides` may set provider/model/cli/effort/replicas/capabilities — **not** prompt/playbook.
- `TeamMemberConfig` exists only in memory after `materializeRosterSlot()` at connect.

### Personal profile (`PersonalProfile`)

Single-agent identity (`agent`, `activePresetId`). Optional session-level `expertKey` selects a catalog expert for Simple launch without mutating this file.

## Session (`session.json`)

Personal Simple launch with expert:

```json
{
  "sessionId": "...",
  "sessionTeam": "",
  "expertKey": "teampilot/builtin/architect"
}
```

No persisted overlay blob — persona is live-resolved from catalog at connect (same as team roster slots).

## Related docs

- [Expert Hub design spec](superpowers/specs/2026-07-05-expert-hub-design.md) — teams as expert collections
- [AGENTS.md](../AGENTS.md) — architecture overview for AI assistants
- [README.md](../README.md) — user-facing feature descriptions

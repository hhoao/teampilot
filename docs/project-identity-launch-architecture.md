# Project / Identity Launch Architecture

Decouples **project (a working directory)** from **launch identity (a team, or
simple/personal mode)**. A project stops being `team × directory`; the team or
personal mode is chosen at the moment a project is opened, via an "open with…"
launch dialog.

## Problem

Today a project is keyed by `(teamId, primaryPath)`
(`SessionRepository.createProject`, `client/lib/repositories/session_repository.dart`).
To work on one directory `D` with team A, team B, and personal mode, the user
must create **three** projects, each time re-picking `D` in the new-project
dialog (`client/lib/pages/home_workspace/home_workspace_new_project_dialog.dart`).
The result is a combinatorial explosion of projects (`N teams × M directories`),
each with its own runtime tree, and a navigation model where the directory — the
thing the user actually cares about — is buried one level under "team".

The personal/team split is also a **project-level hard fork** wired through the
UI:

- `HomeWorkspaceProjectPage` branches on `isPersonal = project.teamId.isEmpty`
  and renders two different bodies/rails
  (`client/lib/pages/home_workspace/project/home_workspace_project_page.dart:145`).
- `ProjectConfigSection` exposes `personalSections` (full surface) vs
  `teamSections` (`settings` only)
  (`client/lib/pages/home_workspace/project/project_config_section.dart:15`).
- The home right pane lists projects filtered by the selected team
  (`HomeWorkspaceContent._projectsForTeam`, filters `p.teamId == team.id`,
  `client/lib/pages/home_workspace/home_workspace_content.dart:222`).

## Core model: directory is the project, identity is chosen at launch

```
Project        = directory(s) + name + icon            (no teamId)
Launch identity = personal  |  team:<teamId>           (chosen when opening)
Session         = belongs to a project, carries its identity in sessionTeam
```

A single project (directory) hosts sessions of **any** identity. Opening the
project asks which identity to launch as; the workbench then resolves config and
launch by that identity, and lists only that identity's sessions.

`AppSession.sessionTeam` (`client/lib/models/app_session.dart:82`) already
carries the stable team id (empty = personal), so the session side of this model
mostly exists. The work is: remove `AppProject.teamId` as the launch key, and
re-key the launch/config chain off the **chosen identity** instead of the
project's team.

### Identity

```dart
sealed class LaunchIdentity {}
class PersonalIdentity extends LaunchIdentity {}      // simple mode
class TeamIdentity extends LaunchIdentity { final String teamId; }
```

Encoded on the project route as a query param, e.g.
`/home-v2/project/{projectId}?as=personal` or `?as=team:{teamId}`.
`HomeWorkspaceProjectPage` reads `as` and drives everything off it instead of
`project.teamId`.

## UX flow

1. Left sidebar: **全部项目 (All Projects)** entry → right pane shows the
   project grid (`HomeWorkspaceProjectsTab`), now listing **all** projects
   (directories), team-agnostic.
2. Click a project card → **launch dialog** (new):
   - Options: **简单模式 (personal)** + each team.
   - Teams sorted by "most recently used **for this project**", derived from
     session history (newest `AppSession.updatedAt` whose `sessionTeam`
     matches), no new store needed for ordering.
   - **记住选择 (remember)** checkbox. When set, future clicks on this card
     **skip the dialog** and open with the remembered identity.
   - Escape hatch when remembered: a `▾` on card hover / right-click
     "以其他身份打开 (open with another identity)" re-opens the dialog.
3. On confirm → navigate to `/home-v2/project/{projectId}?as=<identity>`.
4. Workbench opens for that identity:
   - Lists **only** sessions whose `sessionTeam` matches the chosen identity.
   - New sessions inherit the chosen identity.
   - Config/manage surface resolves by identity (personal → full per-project
     surface; team → team's surface, edited under `/team-config/*`).

### Per-project launch prefs (new small store)

Mirror `HomeWorkspaceProjectDisplayPrefsStore` /
`HomeWorkspaceProjectFavoritesStore`:

```
{ projectId: { lastIdentity: "personal" | "team:<id>", remember: bool } }
```

`lastIdentity` pre-selects the dialog; `remember` skips it.

## What changes

| Area | File | Change |
|------|------|--------|
| Model | `models/app_project.dart` | **delete** `teamId` from `AppProject` (field, json, copyWith, ==). No migration read — old field is simply gone |
| Repo | `repositories/session_repository.dart` | `createProject(primaryPath)` — no `teamId` param; dedup by path only. Delete the `teamId`-keyed branch entirely |
| Launch | `services/session/session_lifecycle_service.dart`, `launch_command_builder.dart` | resolve team/config by **chosen identity**, not `project.teamId` |
| Sidebar | `pages/home_workspace/home_workspace_sidebar.dart` | add **全部项目** entry; **remove 个人/简单模式** entry |
| Home pane | `pages/home_workspace/home_workspace_content.dart` | projects grid lists **all** projects; **remove team "项目" tab** + `_projectsForTeam` filter; team view = config only |
| Project grid | `pages/home_workspace/home_workspace_projects_tab.dart` | card click → launch dialog (not direct `context.go`) |
| Launch dialog | `pages/home_workspace/` (new) | identity picker + recent sort + remember |
| Launch prefs | `services/home_workspace/` (new) | per-project `{lastIdentity, remember}` store |
| Project page | `pages/home_workspace/project/home_workspace_project_page.dart` | `?as=` is **required**; if missing (e.g. hand-typed URL) redirect to the project grid + open the launch dialog. Delete the `isPersonal = teamId.isEmpty` fork |
| New project | `pages/home_workspace/home_workspace_new_project_dialog.dart` | drop team selection; directory + name only |
| Config sections | `pages/home_workspace/project/project_config_section.dart` | choose personal vs team surface by identity, not project type |

## No migration

The project has no users yet, so there is **no migration and no backward
compatibility**. The old `(teamId, primaryPath)` data model is simply replaced.
Any pre-existing on-disk workspace data from the old shape is discarded — wipe
`workspace/projects/` if a dev machine still holds it. Nothing in the codebase
reads the old `teamId` field or a default personal project.

Consequently `ensureDefaultPersonalProject`, `AppProject.defaultPersonalId`, and
`isDefaultPersonal` are **deleted**, not retired — personal mode is purely a
launch identity now, with no seeded built-in project behind it.

## Phasing

Clean cut — the old model never coexists with the new one. Order is just for
landing the change in reviewable pieces.

1. **Model + service.** Delete `AppProject.teamId`; introduce `LaunchIdentity`;
   re-key launch/config resolution (`SessionLifecycleService`,
   `launch_command_builder`) off the identity. No fallback to `project.teamId` —
   it no longer exists. Delete `ensureDefaultPersonalProject` /
   `defaultPersonalId` / `isDefaultPersonal`.
2. **Routing + launch dialog.** Add the required `?as=` param, the dialog, and
   the per-project launch-prefs store; card-click → dialog. Project page reads
   (and requires) `?as=`.
3. **Navigation.** Add **全部项目**; grid lists all projects; remove the team
   "项目" tab, the left "简单模式" entry, the `_projectsForTeam` filter, and the
   `isPersonal = teamId.isEmpty` fork.

All steps ship together as one cohesive change.

## Open questions

- Should "记住选择" be per-project (proposed) or also offer a global default?
- Recent-team sort: per-project (proposed) vs global most-recently-used.
- Whether the team view keeps a read-only "directories this team has worked in"
  list for discoverability (derived from sessions), now that it no longer owns
  projects.

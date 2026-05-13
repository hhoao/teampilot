# Team-Scoped Sessions Design

## Goal

Add an optional session mode where the selected team owns the visible project
and session workspace. When the mode is enabled, switching teams shows only the
projects and sessions associated with that team. When disabled, the app keeps
the current global project/session behavior.

## User Behavior

- A new session setting named `scopeSessionsToSelectedTeam` controls the mode.
- The setting defaults to `false` for backward compatibility.
- When the setting is enabled, new sessions are tagged with the currently
  selected `TeamConfig.id`.
- The left sidebar lists only sessions whose `AppSession.sessionTeam` matches
  the selected team id.
- Projects appear only when they have at least one visible session for the
  selected team, or when all sessions under that project are still visible.
- Switching teams updates the visible project/session list without changing the
  stored global session data.
- Existing untagged sessions stay available in global mode. In team-scoped mode
  they are hidden until a future migration or explicit reassignment feature is
  added.

## Data Model

Reuse `AppSession.sessionTeam` as the owning team id for UI scoping. Existing
launch code currently stores a temporary CLI team directory name in the same
field after a process starts. To avoid losing the UI owner, the implementation
will add a separate persisted field for the launch team name:

- `AppSession.sessionTeam`: stable UI owner team id.
- `AppSession.launchTeam`: temporary CLI team directory name used to launch or
  resume shell processes.

Older session JSON without `launchTeam` continues to load. Existing sessions
whose `sessionTeam` contains old temporary launch names remain unowned for the
new scoping behavior unless they match a real team id.

## State Flow

`SessionPreferences` stores the new boolean setting and the settings page
exposes it as a switch. `main.dart` wires the preference value and selected team
into `ChatCubit`.

`ChatCubit` keeps loading all projects and sessions from `SessionRepository`.
It also tracks:

- current selected team id
- whether team scoping is enabled

It exposes derived visible lists that filter by selected team when enabled.
The sidebar reads the derived lists instead of raw global state.

## Session Creation

All session creation paths that happen in a selected team context pass that
team id to `SessionRepository.createSession`. This includes:

- creating a new session from a project in the sidebar
- creating the default persisted chat tab for the current workspace
- creating the first session when adding a new project

When team scoping is disabled, sessions may still be tagged with the current
team id so enabling the mode later can immediately show the expected sessions.

## Error Handling

If no team is selected while team scoping is enabled, the visible project and
session lists are empty. Corrupt session files continue to be skipped by the
repository as they are today.

## Testing

Add focused tests for:

- `SessionPreferences` JSON/default/copy behavior for the new setting.
- `SessionPreferencesCubit` persistence for the new setting.
- `SessionRepository.createSession` persists a stable session team id.
- `ChatCubit` visible project/session lists filter by selected team and update
  when the selected team or setting changes.
- Sidebar session creation passes the current team id through `ChatCubit`.

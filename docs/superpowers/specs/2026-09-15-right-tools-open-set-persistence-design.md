# Right Tools Open-Set Persistence Design

## Goal

The right-tools tab strip remembers which tools the user opened, across
session-type switches and app restarts. Switching to a team session must bring
back members and mailbox without a settings page, and must still auto-open
those two if the user has never opened or dismissed them.

## Current behavior

`WorkspaceToolsCubit` stores open/selected ids **in memory, per workspace tab**.
`TabbedPanel.pruneToAvailable` drops ids that are not in the current catalog.
Members, mailbox, and board leave the catalog in a simple/personal session, so
they are deleted from the open set. Switching back to a team session does not
restore them.

Mixed-mode teams seed `members` / `mailbox` / `board` only when the open set is
empty (`RightToolIds.mixedTeamDefaults` + `openDefaultsIfEmpty`). If file tree
or git is already open, the seed is skipped. Native teams never seed.

Layout settings (`membersVisible`, `fileTreeVisible`, …) only control catalog
membership. `rightToolsVisible` only shows or hides the pane. Neither field is
the open-tab set.

## Design

One global remembered open set for **every** right-tool id (`members`,
`fileTree`, `git`, `mailbox`, `board`, `search`). Same rules for all of them.
No new settings UI. The pane stays collapsed unless the user already showed it.

### 1. Remembered state

Persist three fields on `LayoutPreferences` (and therefore `LayoutCubit`):

| Field | Meaning |
| --- | --- |
| `rightToolOpenIds` | Tools the user currently wants open, in tab order. Unavailable tools stay in this list. |
| `rightToolSelectedId` | Last selected id. Kept even when that tool is not in the current catalog. |
| `rightToolDismissedIds` | Tools the user explicitly closed. Defaults never revive these. |

Missing JSON keys mean empty lists / null selected: first run.

On load, drop ids that are not in `RightToolIds`. Preserve order for known ids.

### 2. Display vs memory

The strip shows `rightToolOpenIds ∩ current catalog`. It does **not** remove
unavailable ids from memory. Closing a workspace tab does not clear the set.

Effective selected id: the persisted selected id if it is currently visible;
otherwise the last visible open id. The persisted selected id is unchanged
until the user selects or closes a visible tab.

### 3. User actions (unified)

- **Open:** add to `rightToolOpenIds` if missing, select it, remove it from
  `rightToolDismissedIds`.
- **Close:** remove from `rightToolOpenIds`, add to `rightToolDismissedIds`.
  Reselect a neighbor among remaining **visible** ids; persist that selection
  when it is non-null.
- **Select:** persist `rightToolSelectedId`.

These apply to file tree, git, search, board, members, and mailbox the same way.

### 4. Team entry seed

When the catalog is that of a team session (native or mixed, not personal),
for each id in `[members, mailbox]` in that order:

- skip if it is not in the current catalog (native has no mailbox);
- skip if it is already in `rightToolOpenIds`;
- skip if it is in `rightToolDismissedIds`;
- otherwise append it to `rightToolOpenIds`.

If the seed appended at least one id and nothing visible is selected, select
`members` when that id was opened, otherwise the first newly seeded visible id.

This runs whenever the team catalog is shown (session switch, not only the
first mixed-team visit). Closing mailbox records it as dismissed, so later
team sessions do not open it again. Opening mailbox later removes the
dismissed mark.

A native session does not write mailbox into the open set. After a later
switch to mixed, mailbox is available, not open, and not dismissed, so the
same seed opens it once.

Board is not part of this seed. It opens only if the user opened it.

An empty `rightToolOpenIds` does **not** suppress this seed. Only
`rightToolDismissedIds` does. Unrelated layout saves that persist empty open
and dismissed lists must still allow members/mailbox to seed on team entry.

Replace `mixedTeamDefaults` / `openDefaultsIfEmpty` first-visit seeding with
this rule. Do not keep a mixed-only special case.

### 5. Ownership

`LayoutPreferences` is the source of truth and the restart persistence.

`WorkspaceToolsCubit` keeps the mutation API used by `TabbedPanel`, but the
open/selected/dismissed maps become **one global set** (scope id is ignored for
storage). Hydrate from layout preferences after `LayoutCubit.load` and write
back on every mutation (including team seed). Split panes and extra workspace
tabs share the same strip. Do not keep a parallel per-scope map.

Put seed / dismiss / visible-intersection logic in a small pure helper next to
`RightToolIds` (for example `RightToolOpenSet`) so cubit methods stay thin and
unit-testable without widgets.

`TabbedPanel` still intersects with the catalog for display. Stop using prune
as a persistence delete: `pruneToAvailable` must not drop ids that are merely
unavailable in this session type. Unknown ids (not in `RightToolIds`) may still
be stripped on load.

Single-tool auto-open in `TabbedPanel` (catalog length 1 and empty visible
open set) stays. That open is a user-visible mutation and therefore persists
and clears dismissed for that id.

### 6. Layout model wiring

Extend `LayoutPreferences` constructor, `fromJson`, `toJson`, `copyWith`, and
the manual constructor in `withAtLeastOneToolVisible`. Add a `LayoutCubit`
write-through for the open-set triple. Missing JSON keys parse as empty lists /
null selected. After that, empty lists are real values: no open tabs, no
dismissed tabs. Team seed still runs against that empty dismissed list.

## Tests

1. `LayoutPreferences` round-trip and unknown-id stripping for the three
   fields; missing keys default to empty / null.
2. `RightToolOpenSet` (or equivalent): open/close/select; close records
   dismissed; re-open clears dismissed; visible intersection keeps hidden ids.
3. Team seed: available members/mailbox append when not open and not
   dismissed; mailbox skipped when not in catalog; dismissed mailbox is not
   revived; file tree already open does not block the seed.
4. Native then mixed: mailbox seeds on the mixed catalog without having been
   stored during native.
5. Cubit/widget: personal → team restores remembered members/mailbox; closing
   mailbox then switching away and back leaves it closed; restart hydration
   uses saved lists.
6. Existing `WorkspaceToolsCubit` per-scope tests update to the global set.
   Mixed first-visit-if-empty tests are replaced by the seed cases above.

Use `cd client && dart run tool/run_tests.dart …` and `flutter analyze`.

## Scope and non-goals

- No settings row for default open tabs.
- Do not auto-show the right-tools pane (`rightToolsVisible` unchanged).
- Do not remember a different set per workspace or per team.
- Catalog visibility switches (`membersVisible`, …) stay as they are.
- Do not auto-seed board or file tree.
- Personal/simple sessions have no extra defaults beyond the unified
  remember-last behavior and the existing single-tool auto-open.

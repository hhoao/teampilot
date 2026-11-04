# User-message branches

**Date:** 2026-11-04

## Problem

The first build of this feature treated a conversation as a linear list of
turns and gave it a rewind control: the message that closed a turn offered
`< 1 / 2 >` and each step restored the seat's runtime bytes. That is not how a
conversation is actually edited. What a user wants is to change what they said:
edit a user message, get a different answer from there, and keep the old answer
next to it on another branch.

Editing a user message changes everything below it. Those messages belong to a
different branch, and the agent's own memory has to match the branch on screen,
because the CLI keeps the conversation, not TeamPilot.

## Goals

- Edit a user message in place and resend it as a new version of that message.
- Keep every version of the conversation as a branch, and switch between them.
- After a switch the agent memory, the transcript, and the screen all show the
  same branch.
- One mechanism for personal ACP and personal PTY sessions.
- Reuse the per-seat private Git snapshot that already exists.

## Non-goals

- Editing assistant or tool messages. Only user messages carry a branch point.
- Rewinding to an arbitrary turn without editing (the old arrow control).
- Team sessions, SSH seats, Android, and hosts without `git`.
- Project / worktree files. Only `sessions/<id>/runtime/` is restored.
- Merging branches, or deleting old branches.

## Decisions

| # | Decision |
|---|---|
| D1 | A branch point is a user message. Each version of that message starts a sibling turn. |
| D2 | The branch tree is the commit graph of the seat's existing private rewind repository (`sessions/<id>/rewind/<seat>/`). No second store. |
| D3 | Each checkpoint commit records the user message that opened its turn (`Turn-User`) and a millisecond timestamp (`Turn-At`). |
| D4 | Siblings are commits with the same parent commit. They list oldest first by `Turn-At`. |
| D5 | Switching to a version restores the newest descendant of that version's commit, so the whole branch comes back, not just that one turn. |
| D6 | Switching is immediate: stop the seat, write the tree back, relaunch. The screen never shows a branch the agent does not remember. |
| D7 | Editing restores the parent commit, then sends the edited text through the normal submit path. The new turn's checkpoint becomes a sibling of the original. |
| D8 | A failed send after the restore puts the previous branch tip back before surfacing the error. |
| D9 | Fork copies the branch through the selected turn into a new personal session. The source stays untouched. |

## Tree model

Each completed turn already writes one commit whose parent is
`refs/rewind/checked-out`. Two additions make it a tree:

```
checkpoint

Turn-Message: <last message id of the turn>
Turn-User: <user message id that opened the turn>
Turn-At: <epoch milliseconds>
Native-Session: <id, or empty>
```

- `Turn-User` is the anchor the UI uses. The caller supplies it: ACP takes the
  last user-role message of the turn from its message list, PTY takes it from
  the loaded seat history when the turn commits. A commit without it (written
  before this design) offers no version control and cannot be edited.
- `Turn-At` gives siblings a stable order even when two commits land in the
  same second.
- The first turn of a seat gets a parent too: when `checked-out` is missing,
  the store writes an empty root commit (empty tree, no parent) at
  `refs/rewind/root` and uses it as the parent. Editing the first user message
  restores that root, which clears the seat's included files, so the next
  launch starts a new agent session.
- `refs/rewind/checked-out` is the tip of the branch on screen.

Derived views, all from `git log` over the keep refs:

| View | Rule |
|---|---|
| Turn commit of a user message | the commit whose `Turn-User` equals that id |
| Siblings of a version | commits sharing its parent |
| Current version index | position of the turn commit among its siblings, ordered by `Turn-At` |
| Branch tip of a sibling | the descendant of that commit (inclusive) with the greatest `Turn-At` |

## Editing a user message

Trigger: the action bar of a user message that has a `Turn-User` commit on the
current branch.

1. Refuse while a turn is in flight, while a restore is running, or while the
   seat is not a local personal seat with `git` on `PATH`.
2. Resolve the turn commit `C` of the message and its parent `P` (the root when
   the message is the first turn).
3. Stop the seat, restore `P`, relaunch. The thread now shows the parent
   branch: the edited message and everything below it disappear.
4. Send the edited text through the normal submit path.
5. The turn ends and checkpoints with parent `P`, so the new commit is a
   sibling of `C`. The thread shows the new branch and the message reports the
   new version.
6. Unchanged text closes the editor without a new turn or branch.

## Switching versions

1. Refuse under the same conditions as editing.
2. Resolve the sibling commit `S` for the chosen version.
3. Resolve the branch tip of `S` (D5).
4. Stop the seat, restore that tip, relaunch.
5. The thread reloads from the restored transcript and reports `S`'s version
   index again.

The action bar of a user message shows `‹ index / count ›` only when the
message has at least two versions. The arrow at either end is disabled.

## Fork

"Fork from here" on a user message copies the commit of that turn, with all its
ancestors, into a new personal session and opens it. The new session keeps the
same branch structure, so its versions remain switchable. A failure after the
new session directory exists deletes that directory.

## Failures

- Restore failure: write the previously checked-out tree back, then surface the
  error. Never relaunch onto a half-applied tree.
- Relaunch failure: leave the files at the target checkpoint and use the
  existing launch error. Never fall through to `session/new` for an ACP seat
  that was supposed to load a restored session.
- Send failure after a successful restore: restore the original branch tip,
  keep the editor open with the edited text, and surface the existing send
  error.
- A checkpoint that cannot read part of the runtime tree skips that path and
  still commits.

## UI

- User message action bar: edit, `‹ index / count ›`, fork from here, copy,
  export. Assistant messages keep copy and export only.
- Editing replaces the bubble with a multi-line field prefilled with the
  original text. Enter sends, Shift+Enter inserts a newline, Escape cancels.
  The bar of that message is hidden while editing.
- Everything is disabled while a turn is in flight or a restore / fork / send
  is running, and hidden for team sessions, SSH seats, Android, and hosts
  without `git`.
- After a switch the thread sticks to the end of the restored branch.

## Modules

- `services/chat/rewind/seat_rewind_store.dart` gains the turn metadata, the
  root commit, sibling and tip lookup, and a restore that empties the seat for
  an empty target tree.
- `services/chat/rewind/seat_branches.dart` (new) is the read model: turn
  commit per user message, sibling list, version index, branch tip. No UI and
  no transcript parsing.
- `ChatCubit` exposes `switchSeatVersion`, `editSeatTurn`, and the existing
  fork entry; all three go through `RewindForkService` for stopping and
  relaunching.
- The history host loads the branch read model; the thread renders the control
  on user messages; `ai_message_ui` gains `onEdit` and an editing mode on the
  bubble.
- Labels go in `app_en.arb` and `app_zh.arb`.

## Tests

- Turn metadata: a commit records `Turn-User`, `Turn-At`, and the parent; the
  first turn's parent is the root; restoring the root clears the seat's files
  and sidecars.
- Siblings: two turns with the same parent list as two versions ordered by
  `Turn-At`; the version index matches; a single version shows no control.
- Branch tip: after a later turn extends one sibling, switching to it restores
  that extension, not the sibling itself.
- Edit: restore lands on the parent, the new commit is a sibling, the old
  commit stays reachable, unchanged text creates nothing.
- Failure: restore failure rolls back; send failure restores the previous tip;
  fork copies only through the selected turn and deletes the new session on
  failure.
- UI: the control appears only on user messages with two or more versions;
  edit opens, sends, and cancels; the actions are disabled while in flight and
  while a restore runs.
- Scope: team, SSH, Android, and no-`git` hide every entry point.

## Relation to the previous design

`docs/superpowers/specs/2026-11-03-session-rewind-fork-design.md` still owns
the private repository, path rules, restore, and fork materialization. This
document replaces its "Rewind UI" section: the turn-level arrow control and its
position on the closing assistant message are gone; the branch point is the
user message, and versions are edited rather than only visited.

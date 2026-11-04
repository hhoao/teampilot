# Session rewind and fork

**Date:** 2026-11-03

## Problem

ACP has no standard rewind. `session/fork` is an unstable draft and does not
carry a message anchor. Each CLI stores one conversation as many files under
its config directory (JSONL plus side directories, Codex rollouts, OpenCode's
SQLite database and its `-wal`/`-shm`, Cursor's isolated home). Parsing those
layouts per CLI, or clearing only `acp-session.json`, either drops the agent's
prefix or misses files the next `session/load` / `--resume` still reads.

TeamPilot already isolates each seat in `sessions/<id>/runtime/`. Rewind and
fork should snapshot that directory and restore it, and should not touch the
user's project repository.

## Goals

- After every completed turn, record a checkpoint of that seat.
- From the message that closed the turn, rewind this seat to that checkpoint
  or fork it into a new personal session.
- Rewind and fork restore the seat's runtime bytes, so the agent resumes the
  prefix through the existing launch path.
- Later checkpoints stay reachable after a rewind.
- One mechanism for personal ACP, mixed ACP seats, and PTY seats.

## Non-goals

- Rewinding or forking files in the user's project / worktree.
- Aligning checkpoints across team seats. A checkpoint belongs to one seat.
- Forking a team session into another team session. Fork creates one personal
  session from the selected seat.
- Deleting old checkpoints.
- Parsing or truncating a CLI's transcript format.
- Seats whose agent and runtime live on another machine (SSH work plane).
- Android.

## Decisions

| # | Decision |
|---|---|
| D1 | One private Git repository per seat. `GIT_DIR` is `sessions/<sessionId>/rewind/<seatKey>/`. `GIT_WORK_TREE` is that session's `runtime/` directory. Nothing is written into `runtime/<tool>/` as a `.git` directory, and nothing is written into the user's project `.git`. |
| D2 | `seatKey` is `personal` for a simple session and the roster member id for a mixed seat. |
| D3 | Add and checkout are limited to that seat's paths. Other seats' files are never in the tree and are never written or deleted. |
| D4 | A checkpoint is taken only after the turn has finished. ACP waits until that turn's transcript flush has completed. PTY waits until the seat is idle. The recorded message id is the last message of that turn. |
| D5 | Commits are append-only. Rewind moves `checked-out` and the work tree only. A new turn moves `live` to a commit whose parent is the current `checked-out`. Nothing deletes commits. |
| D6 | Shared cache paths and symlinks are excluded and not followed. The existing launch linker restores them on the next start. |
| D7 | Fork does not stop the source seat. It reads the selected commit and writes it into a new personal session. |
| D8 | A failed checkout restores the previously checked-out tree. A failed relaunch leaves the files at the target checkpoint and surfaces the existing launch error. ACP never falls through from a failed `session/load` / `session/resume` into `session/new`. |

## What a checkpoint contains

Paths are relative to `runtime/`.

| Seat | Included paths |
|---|---|
| Personal ACP | `{tool}/`, `acp-transcript.jsonl`, `acp-session.json` |
| Mixed ACP | `{memberId}/{tool}/`, `acp-transcript-<memberId>.jsonl`, `acp-session-<memberId>.json` |
| Personal PTY | `{tool}/` |
| Mixed PTY | `{memberId}/{tool}/` |

Excluded anywhere under those prefixes: `plugins`, `skills`, `node_modules`,
`cache`, and symlinks. Git must not follow symlinks. The exclude list lives in
the private repo's `info/exclude`, not in a `.gitignore` inside the tool
directory.

PTY native session ids live on `AppSession` / the member binding, outside
`runtime/`. Each checkpoint records the native session id that was current when
the turn ended. ACP does not need a separate record: `acp-session.json` is
inside the tree.

Every checkpoint is kept with a ref `refs/rewind/keep/<messageId>` so a later
`git gc` cannot drop it. `refs/rewind/live` is the head new turns extend.
`refs/rewind/checked-out` is the tree currently written into the work tree.
After a rewind these two refs differ. After a new turn they match.

## When the snapshot runs

Hook the existing turn-ended path. ACP waits until
`AcpChatTranscriptWriter` has persisted that turn. PTY snapshots at turn end,
**before** the seat is published idle: the shell latch and the bus turn stay
up until the commit exists, so a queued follow-up or a doorbell delivery
cannot start the next turn while `git add` is still walking `{tool}/`. The
PTY transcript is the CLI files inside `{tool}/`.

- Skip when a rewind or fork is in progress.
- Skip when the seat has no local runtime directory.
- The new commit's parent is `refs/rewind/checked-out` when that ref exists,
  otherwise the first commit has no parent.
- Move both `live` and `checked-out` to the new commit. A previous `live`
  that was not the parent stays reachable through its `keep` ref.
- The commit message records `Turn-Message: <messageId>` and, for PTY,
  `Native-Session: <id>`.

## Restore

Used by rewind and by the initial materialization of a fork.

1. Refuse while this seat's turn is in flight, or while a rewind or fork is
   already running for it.
2. Rewind only: stop this seat's process and wait until it has exited. Other
   seats keep running.
3. Remember `checked-out`.
4. Write the target tree's files for this seat's pathspec.
5. Delete files under that pathspec that are not in the target tree. Do not
   delete excluded paths, symlinks, or anything outside the pathspec.
6. On any failure in steps 4–5, write the remembered tree back the same way
   and surface the error. Do not relaunch onto a half-applied tree.
7. Set `checked-out` to the target.
8. Relaunch this seat through the existing connect path.
   - ACP reads the restored `acp-session.json` and uses `session/load` or
     `session/resume`. A load/resume failure uses the existing session-open
     error and must not open `session/new`.
   - PTY resumes with the native session id stored on that checkpoint.
9. A relaunch failure leaves the files at the target checkpoint.

## Rewind UI

Actions sit on the existing message action bar (the same bar as copy and
export), and only on a message id that has a checkpoint. That is the last
message of a completed turn.

- **Fork from here** is shown on a checkpoint message that is in the
  checked-out transcript.
- The message that closed the checked-out checkpoint shows a version control,
  `<index / count>`, when this seat has at least two checkpoints. Previous
  and next restore that neighboring checkpoint. The ends are disabled.
- Fork and the version control are disabled while a turn is in flight or a
  rewind/fork is running.
- Both are absent when `git` is not on `PATH`, and on seats whose runtime is
  on an SSH work plane.

The live thread shows only the transcript of `checked-out`. Later checkpoints
are not drawn as extra messages. They stay in the rewind repo. Moving the
version control runs restore against the neighboring commit, so the thread
grows or shrinks to that checkpoint.

Sending a prompt while rewound appends a new turn whose parent is the current
`checked-out` commit, then moves `live` and `checked-out` to that commit.
Messages that exist only on the abandoned checkpoints stay reachable through
the version control.

## Fork

1. Create a new personal session in the same workspace: same CLI, same
   folder, no team. Display name is the source name plus a fork suffix.
2. Create its rewind repo and copy commits reachable from the selected
   checkpoint, up to and including that commit. `live` and `checked-out` both
   point at it. Later source commits are not copied.
3. Restore that tree into the new session's `runtime/` using the personal
   path layout (member prefixes are stripped; ACP sidecar names become the
   personal names).
4. Seed `nativeSessionIds` from the checkpoint when it has a native id.
5. Open the new session.
6. If any step after the session directory exists fails, delete that session
   directory. The source session, its process, and its rewind repo stay as
   they were.

## Modules

- `client/lib/services/chat/rewind/` owns the Git repository, pathspec,
  exclude rules, restore, and fork materialization. It does not launch
  processes and does not parse transcripts.
- Turn-ended call sites (`ChatCubit` turn end, ACP turn completion after
  persist) call the store. They do not shell out to Git themselves.
- Rewind and fork operations stop or create sessions through the existing
  launch and session-repository APIs.
- The history thread and `AiMessageActionBar` only render fork and the
  version control. Labels go in `app_en.arb` and `app_zh.arb`.

## Tests

Use a temporary `runtime/` fixture and a `git` on `PATH`. No per-CLI fixture.

- A commit contains one seat's regular files and sidecars, and does not
  contain another seat's files, `plugins`, `skills`, `node_modules`, `cache`,
  or the contents of a symlink.
- Restore writes the target bytes and deletes a seat file that is absent from
  the target, without deleting a sibling seat's file.
- A failed restore puts the previous tree back.
- Turn-end records the last message id. An in-flight turn does not.
- Fork's repo has the selected commit as `live` and does not contain a later
  source commit. A failed fork removes the new session directory.
- The ACP relaunch path reads the session id from the restored sidecar. The
  PTY path uses the id stored on the checkpoint.

## Out of scope for the first implementation

Automatic deletion of old checkpoints, a checkpoint browser other than the
message actions and the version control, and confirmation dialogs. Rewind is
reversible by checking out another retained commit.

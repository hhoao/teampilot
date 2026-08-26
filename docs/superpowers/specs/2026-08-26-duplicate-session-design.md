# Duplicate session with history fork

## Problem

Users cannot duplicate an existing session. The closest feature, workspace clone
(`SessionRepository.cloneWorkspace`), copies every session but resets all CLI
state, so clones always start blank conversations. When a user wants a second,
independent continuation branch of a conversation (e.g. retry a different
direction from the same context), there is no path today.

## Decision

Add **duplicate session**: one source session becomes a new session whose
launch configuration *and* CLI-side conversation history are copied. The fork
continues from the source's last message while remaining fully isolated on disk.

Scope decisions:

- **Simple mode only (v1).** Team / mixed sessions are out of scope; their
  multi-member histories can reuse this mechanism later, per member.
- **All five CLIs supported** (claude, flashskyai, codex, opencode, cursor).
- **Source must be stopped.** Duplication is rejected while the source session
  has a live PTY. Copying a live transcript risks torn JSONL appends and a
  corrupt SQLite WAL (opencode).
- **Zero file mutation beyond the copy itself.** No transcript renames, no id
  rewrites inside CLI state. The fork is: copy the runtime tree verbatim, then
  seed the new session's `nativeSessionIds` so resume/history resolve against
  the copied state. This avoids partial-rename failure modes and any reliance
  on stem-sibling layout conventions (`subagents/`, `workflows/`, …).
- **clientPinned CLIs learn persisted ids.** claude / flashskyai currently
  assume native id == taskId and ignore `persistedNativeId`. They gain the same
  "persisted wins if its transcript exists, else probe taskId" semantics that
  codex / opencode / cursor already implement. Consequence: simple-mode claude
  transcript filenames may legitimately differ from `sessionId` after a fork;
  all equality assumptions are swept to honor persisted ids.

Out of scope: duplicating into a different workspace, team/mixed duplication,
cross-machine (SSH remote) history copy verification.

## How isolation makes this safe

Every CLI keeps its resumable state inside the session's own runtime dir,
addressed by absolute env paths set at launch:

| CLI | State location under `sessions/{id}/runtime/` | Isolation env |
|-----|-----------------------------------------------|---------------|
| claude | `claude/projects/{bucket}/{taskId}.jsonl` | `CLAUDE_CONFIG_DIR` |
| flashskyai | `flashskyai/projects|workspaces/{bucket}/{taskId}.jsonl` | `FLASHSKYAI_CONFIG_DIR` |
| codex | `codex/sessions/**/rollout-*.jsonl` (ids kept) | `CODEX_HOME` |
| opencode | `opencode/opencode.db{,-wal,-shm}` (ids kept) | `OPENCODE_DB` |
| cursor | fake HOME (`chats/`, `projects/**/agent-transcripts/`) | `CURSOR_CONFIG_DIR` + `HOME` |

Copying `{tool}/` wholesale therefore yields a complete, isolated, resumable
state for the fork regardless of which internal ids the CLI uses. The only
TeamPilot-side coupling left is *which* native id to resume, handled by
`nativeSessionIds`.

## Architecture

| Unit | Location | Responsibility |
|------|----------|----------------|
| `SessionRepository.duplicateSession` | `repositories/session_repository.dart` | Under the source-session lock: re-validate (exists, `isSimple`), `createSession` with identical simpleIdentity fields and a fresh sessionId, copy `runtime/{tool}/` tree, seed the fork's native id (postCaptured: source's persisted entry; clientPinned: the source sessionId, since pinned transcripts are never persisted), return the new `AppSession`. On copy failure: best-effort removal of the new session dir + index entry (CLI never launched, so no `destroyCliState`). |
| `ChatCubit.duplicateSession` | `cubits/chat_cubit.dart` | UI-facing validation (simple mode, source terminal not running), calls the repository, opens the new tab and connects immediately on success; l10n error on failure. |
| Sidebar menu item「复制」 | `widgets/sidebar_session_tile.dart` | Context-menu entry beside rename/pin/delete; visibility rules below. |
| clientPinned capability update | `services/cli/claude/capabilities/history/`, `services/cli/flashskyai/capabilities/history/` | `detectNativeId` probes `persistedNativeId` first (existing `pinnedTranscriptExists` machinery), falls back to the current taskId probe; locate prefers the persisted id the same way. |
| Equality-assumption sweep | `_resolveResume` callers, `hasCliState` / `_findCliState`, history locate helpers | Any site that assumes pinned-transcript filename == taskId must also accept the persisted id. All go through capability interfaces; bounded set. |

### Data flow

```
context menu「复制」(enabled: isSimple && source stopped)
→ ChatCubit.duplicateSession(session)
   ├─ guard: session.isSimple && no live PTY for source
   ├─ repo.duplicateSession(source):
   │    ├─ lock source session file; re-check exists && isSimple
   │    ├─ newSession = createSession(
   │    │     same cli/provider/model/effort/presetId/expertKey/folders/
   │    │     workingDirectory, fresh sessionId, display = source + l10n suffix)
   │    ├─ copyTree(sessions/{old}/runtime/{tool}/ → sessions/{new}/runtime/{tool}/)
   │    ├─ seed fork native id:
   │    │     postCaptured → source.nativeSessionIds[tool]
   │    │     clientPinned  (claude/flashskyai, no persisted entry)
   │    │       → source.sessionId  (the pinned transcript filename)
   │    └─ persist + index update; return newSession
   └─ success → requestOpenSession(new, connectImmediately)
      failure → cleanup + l10n error
```

First launch of the fork resolves through the unchanged `_resolveResume` gate:
a persisted id is present, detection runs (session_lifecycle_service.dart:1526),
the updated claude-family `detectNativeId` finds the copied transcript, and the
plan emits `--resume {oldId}` against the fork's own CONFIG_DIR. If the copied
state was deleted by hand, both probes miss and the fork degrades gracefully to
a fresh conversation.

### Repeated duplication

Duplicating twice appends the suffix again (`X（副本）（副本）`). Accepted for v1;
no dedup logic.

## UI behavior

- Menu item states: hidden for team/mixed sessions (v1 unsupported); disabled
  while the source session's terminal is running; enabled otherwise.
- Success: new tab opens and connects immediately — the terminal shows the
  resumed history, making the copy visibly real. Snackbar confirmation.
- Large trees copy asynchronously with a loading affordance on the menu action.
- l10n additions in `app_en.arb` / `app_zh.arb`: menu label, success snackbar,
  failure message, `(copy)` / `（副本）` title suffix.

## Error handling

| Failure | Handling |
|---------|----------|
| Validation fails (team session / running) | Blocked at menu; service layer double-checks and throws typed error → l10n message |
| Copy fails midway | Best-effort recursive delete of the new session dir + index rollback; error surfaced |
| Source deleted between validation and copy | Lock-guarded recheck inside repository operation; fail cleanly |
| Persisted-id transcript missing later | Existing graceful degradation (probe fallback → fresh launch); no extra handling |

## Testing

1. **Capability level:** claude / flashskyai `detectNativeId` + locate prefer a
   persisted id whose transcript exists, fall back to taskId probe otherwise
   (fixture trees on temp fs).
2. **Repository level:** `duplicateSession` happy path — identity fields copied,
   runtime tree copied, `nativeSessionIds` seeded, fresh sessionId/title; failure
   path leaves no partial session behind.
3. **Resume chain:** forked session `_resolveResume` yields `--resume {oldId}`
   for each of the five CLIs (mock fs fixtures).
4. **Widget:** menu three-state matrix (simple-enabled / team-hidden /
   running-disabled).
5. Harness: `setUpTestAppStorage()` / `tearDownTestAppStorage()` conventions;
   filesystem injected.

## Known limitations (v1)

Two accepted gaps, documented so they are not rediscovered as bugs:

- **Windows cursor junction copies.** cursor's fake-HOME isolation
  materializes parts of its runtime tree as NTFS junctions (see the cursor
  capability). When duplicating a cursor conversation whose copied tree
  contains those link entities, `LocalFilesystem.copyTree` skips links instead
  of following them, so the duplicated conversation can resume blank. This is
  no worse than pre-feature behavior (where nothing was copied at all); a full
  physical-home copy is a fast-follow.
- **Liveness guard blind window.** The cubit-level liveness check
  (`_duplicateEnabled`) inspects the source tab when the menu is built. A
  source tab that is staged but not yet running — inside its async prep
  window — still looks idle, so its history could be copied just before the
  terminal goes live. The copy remains a consistent point-in-time snapshot,
  but may miss turns that land between the copy and the terminal going live.


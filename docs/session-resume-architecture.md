# Session Resume Architecture

Unifies "resume a previous session" across all five CLIs behind one capability,
replacing the claude-shaped transcript probe that silently never matched
codex / opencode / cursor.

## Problem

Resume detection lived in `SessionLifecycleService._findCliState`, which probed
the filesystem for a claude-style transcript file named `<ourUuid>.jsonl`. Only
claude and flashskyai produce that, because we pin our UUID with `--session-id`
at creation. codex, opencode and cursor allocate their **own** native session
ids and store them in their own formats/locations, so the probe never matched →
`plan.resume` stayed `false` → no resume flag was ever emitted. cursor's
intended `cursor-agent create-chat` allocation existed only as a code comment.

## Core model: one explicit native id per (session-member, tool)

Every resumable session holds an explicit **native session id** for each CLI it
has run under. Resume is always "resume native id X with this CLI's resume
syntax" — never a "latest in directory" heuristic. New CLI = pick a binding
strategy + implement the capability; no `if (cli == …)` scattering.

| CLI | binding | native id origin | resume invocation |
|-----|---------|------------------|-------------------|
| claude | `clientPinned` | our UUID, pinned via `--session-id` | `--resume <id>` |
| flashskyai | `clientPinned` | our UUID, pinned via `--session-id` | `--resume <id>` |
| cursor | `postCaptured` | cursor-generated; captured from isolated `$CURSOR_CONFIG_DIR/chats/**/<id>/meta.json` | `--resume <id>` |
| codex | `postCaptured` | codex-generated; captured from isolated `$CODEX_HOME/sessions/**/rollout-*.jsonl` | `resume <id>` (subcommand) |
| opencode | `postCaptured` | opencode-generated `ses_*`; captured from isolated `$OPENCODE_DATA_DIR/storage/session/**/*.json` | `--session <id>` |

### Why these strategies (verified on disk)

- **cursor** stores each chat under the **per-session-isolated**
  `$CURSOR_CONFIG_DIR/chats/<workspaceHash>/<chatId>/` with a `meta.json`
  (`hasConversation`, `title`, `updatedAtMs`). So we let cursor mint its own chat
  on the fresh launch and, on reopen, scan that tree and `--resume` the chat with
  `hasConversation: true` and the newest `updatedAtMs`. We do **not** use
  `cursor-agent create-chat`: it makes an empty chat (`hasConversation: false`)
  that diverges from the chat the interactive TUI actually writes to, so resume
  would restore nothing (the bug that motivated this).
- **codex** has no "create with my id" flag, but `$CODEX_HOME` is already
  isolated per session, so the isolated `sessions/` tree contains exactly this
  session's rollout — we capture its uuid. (developers.openai.com/codex)
- **opencode** only had `OPENCODE_CONFIG_DIR` isolated; session JSON lives under
  `OPENCODE_DATA_DIR` (default global). We **also isolate `OPENCODE_DATA_DIR`**
  per session so the captured `ses_*` is unambiguous. (opencode.ai/docs/cli)

There is no out-of-band subprocess and no "resume latest" heuristic: every
binding resolves an explicit native id (clientPinned probes the transcript by our
id; postCaptured scans the CLI's own isolated store).

## Capability

`SessionResumeCapability` (replaces `TranscriptProbeCapability`) owns session
identity detection for one CLI:

```dart
enum ResumeBinding { clientPinned, postCaptured }

abstract interface class SessionResumeCapability implements CliCapability {
  ResumeBinding get binding;

  /// Resolve the native id of an existing resumable session, or null.
  /// clientPinned: probe the transcript file by our id.
  /// postCaptured: scan the CLI's per-session-isolated store.
  Future<String?> detectNativeId(ResumeContext ctx);
}
```

`ResumeContext` carries: `fs`, our `taskId`, the resolved launch `env` (holds the
isolated `CODEX_HOME` / `OPENCODE_DATA_DIR` / `CURSOR_CONFIG_DIR`), transcript
search roots + bucket, and the persisted native id (if any).

## Flow (`SessionLifecycleService._prepareLaunchPlan`)

Resume resolution moves to **after** `_prepareEnv`, because postCaptured
strategies need the resolved isolated config dir from the launch env.

```
env = _prepareEnv(...)                       // establishes CODEX_HOME / CURSOR_CONFIG_DIR / OPENCODE_DATA_DIR
cap = registry.capability<SessionResumeCapability>(cli)
nativeId = await cap.detectNativeId(ctx)      // probe (clientPinned) / scan (postCaptured)
plan = LaunchPlan(
  resume: nativeId != null,
  createSessionId: nativeId == null && clientPinned ? taskId : null,  // postCaptured never pins
  resumeSessionId: nativeId,
  nativeSessionIdToPersist: clientPinned ? null : nativeId,  // caller persists; clientPinned id == taskId
  isFreshConversation: nativeId == null,      // drives cursor identity seeding
  ...
)
```

The caller (`session_launch_service`) persists `nativeSessionIdToPersist` onto
`SessionMemberBinding.nativeSessionIds[cli.value]` (team) or
`AppSession.nativeSessionIds` (personal) via `SessionRepository`, so a captured
codex/opencode/cursor id is reused next time without re-scanning.

Adapters emit the CLI-specific form from `context.fixedSessionId` (create) /
`context.resumeSessionId` (resume): claude/flashskyai `--session-id`/`--resume`,
cursor `--resume`, codex `resume <id>` subcommand prefix, opencode `--session`.
cursor seeds member identity as the opening prompt only when
`context.isFreshConversation` (no resume id was found).

## Persistence

`SessionMemberBinding` gains `Map<String,String> nativeSessionIds` (tool.value →
native id) for team sessions; `AppSession.nativeSessionIds` holds the same for
personal (single-agent) sessions, which have no roster. clientPinned leaves both
empty (native id == taskId). Both are **additive, optional JSON fields** — no
schema-version bump or migration: pre-existing codex/opencode/cursor sessions
simply weren't resumable before and become resumable once they record an id on
the next launch.

Persisting (`SessionRepository.recordNativeSessionId`) writes disk **and**
`session_launch_service` mirrors it into the in-memory `_state.sessions` /
`tab.persistedSession`, so a same-run reconnect/reopen reuses the id instead of
re-allocating.

## Files

- `models/session_member_binding.dart` — `nativeSessionIds` map + json.
- `services/cli/registry/capabilities/session_resume_capability.dart` — new interface (removes `transcript_probe_capability.dart`).
- `services/cli/registry/capabilities/resume/*` — per-CLI strategy impls.
- five `registry/tools/*_cli_tool.dart` — swap `transcriptProbe` → resume capability.
- `services/session/session_lifecycle_service.dart` — reorder + delegate to capability; thread native id.
- `services/session/shell_launch_spec.dart` — `LaunchPlan` native-id fields.
- `services/cli/cli_tool_adapter.dart` — codex `resume <id>` prefix; cursor/opencode confirmed.
- `services/cli/registry/config_profile/opencode_config_profile_capability.dart` — isolate `OPENCODE_DATA_DIR`.
- `services/cli/cli_tool_locator.dart` — resolve the cursor executable for `create-chat`.
- `cubits/chat/session_launch_service.dart` — persist native id (disk + in-memory).
- `app/app_shell.dart` — wire `defaultResumeSubprocessRunner` (null in tests).

The out-of-band `create-chat` runs through an injected `ResumeSubprocessRunner`
(`SessionLifecycleService(resumeSubprocessRunner:)`), gated to local filesystems;
WSL/SSH backends can't pre-allocate and emit a `cli_resume_prealloc_unavailable_*`
launch warning instead of silently degrading.
</content>
</invoke>

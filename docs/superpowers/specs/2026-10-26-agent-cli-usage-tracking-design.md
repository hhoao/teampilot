# Agent CLI Usage Tracking Design

## Goal

Record per-request token usage for agent CLIs launched by TeamPilot, on both
local and remote (SSH) home planes, without depending on a local proxy, and
show it in a dedicated usage page inside the workspace home.

The implementation has two slices:

1. **Foundation**: per-CLI extraction capability, home-plane usage store,
   incremental cursors, sync service.
2. **UI**: a workspace-home "Token 用量" pane with summary cards, filters,
   grouping, and a manual sync action.

Scheduling, pricing, and proxy interception remain out of scope.

Decisions locked with the user (2026-10-26):

- Approach **A**: scan per session through TeamPilot's existing isolated CLI
  `CONFIG_DIR`, not a cc-switch-style global `~/.claude` walk.
- First CLIs: **Claude Code, Codex, OpenCode**.
- Store usage on the **current home plane** through `Filesystem` (JSONL), not
  SQLite. Remote app data cannot open a SQLite file over SFTP.
- The UI is a **standalone left-sidebar entry** (`Token 用量`), next to the
  existing provider `余额与用量` entry, not a settings dialog section.
- Sync is manual in this slice; no startup or periodic full scan.
- No changes to chat/history behavior. Usage extraction is additive and reads
  the same transcripts the history loader already reads.

HTML design reference:
`docs/superpowers/designs/2026-10-26-agent-cli-usage-ui.html`.

## Why this shape

TeamPilot does not run one shared CLI config per user. `RuntimeLayout` links
each launch into a per-session tree:

```text
cli-defaults/{tool}/                         app templates
identities-runtime/{profileId}/{tool}/       team identity
workspace/.../config/{tool}/                 workspace overrides
workspace/.../sessions/{sessionId}/runtime/  session CONFIG_DIR
  runtime/{tool}/                            Simple / native seat
  runtime/{memberId}/{tool}/                 mixed seat
```

Claude writes `projects/**/*.jsonl` under that `CONFIG_DIR`; Codex writes
`sessions/**/rollout-*.jsonl` under its `CODEX_HOME`; OpenCode writes
`opencode.db`. A global `~/.claude` walk would miss most TeamPilot sessions,
and would lose the session/member attribution that makes TeamPilot different
from cc-switch.

Scanning per session also reuses `SessionHistoryContextBuilder`, which already
resolves the exact roots, env (`CODEX_HOME`, `OPENCODE_DB`), and bucket the
history loader uses. One locator, two consumers.

## Non-goals

- Session header meter and per-message inline usage.
- Cost calculation and model pricing. `costMicroUsd` is stored only when a CLI
  reports it; no pricing table is consulted and the first UI does not show it.
- Periodic background scan. The sync service is callable; scheduling is a
  follow-up.
- Local proxy request logging. TeamPilot has no owned HTTP proxy.
- CLI sessions started outside TeamPilot (for example a bare terminal
  `claude`). A global-roots mode can be added later without changing the
  store or capability contract.
- ACP `usage_update` live context window. It is a separate, cheap follow-up.
- Importing `~/.cc-switch/cc-switch.db`.

## Layering

| Piece | Path | Responsibility |
|-------|------|----------------|
| Event model | `models/session_usage.dart` | Immutable event, semantics, source/cursor types |
| Capability port | `services/cli/registry/capabilities/session_usage_capability.dart` | `CliCapability` implemented per CLI |
| CLI parsers | `services/cli/{claude,codex,opencode}/capabilities/usage/` | Source discovery + incremental parse |
| Target enumeration | `services/usage/usage_scan_target_provider.dart` | Sessions/seats → `UsageScanContext` |
| Store ports | `services/usage/usage_store.dart`, `usage_cursor_store.dart` | Persistence seams |
| JSON store | `services/usage/json_usage_store.dart`, `json_usage_cursor_store.dart` | Home-plane implementation |
| Sync service | `services/usage/session_usage_sync_service.dart` | Lock, iterate, upsert, advance cursors |
| Aggregation | `services/usage/usage_aggregator.dart` | Pure summary/filter/group functions |
| UI state | `cubits/session_usage_cubit.dart` | Load cached events, manual sync, filters |
| UI page | `pages/usage/session_usage_page.dart` | Sidebar pane, cards, chart, table |
| UI wiring | `pages/home_workspace/home_workspace_global_section.dart`, `home_workspace_sidebar.dart` | `HomeGlobalView.usage` entry + pane |
| Attribution | `services/usage/usage_attribution_provider.dart` | Session/team/member display names |
| Paths | `services/storage/app_paths.dart` | `usage/` files under app data |

Registration follows the CLI rule: each `CliToolDefinition` adds a
`SessionUsageCapability`. No `if (cli == …)` in the sync service, cubits, or
pages.

## Models

```dart
enum UsageInputSemantics { fresh, total }

enum UsageSourceKind { jsonl, sqlite }

final class SessionUsageEvent {
  final String requestId;          // dedup key, CLI-scoped
  final CliTool cli;
  final String model;
  final int inputTokens;           // as reported; semantics below
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int cacheCreation1hTokens; // Claude 1h TTL subset
  final UsageInputSemantics inputSemantics;
  final int timestampMs;
  final String sessionId;
  final String memberId;           // '' for Simple seats
  final String teamId;             // '' for Simple seats
  final bool isFinal;              // settled answer vs partial snapshot
  final int? costMicroUsd;         // CLI-reported only
}
```

`inputSemantics` records the wire meaning, exactly as cc-switch's
`input_token_semantics`:

- **fresh**: `inputTokens` excludes cache (Claude, OpenCode).
- **total**: `inputTokens` includes cache read/write (Codex, Gemini, Grok).

Aggregation must normalize with `fresh = input - cacheRead - cacheCreation`
for `total` rows. The model never rewrites the raw values.

`requestId` namespaces:

| CLI | Format |
|-----|--------|
| Claude | `claude:{message.id}` |
| Codex | `codex:{threadId}:{deltaIndex}` |
| OpenCode | `opencode:{messageId}` |

CLI scoping prevents an id collision when two CLIs reuse the same envelope id.
Claude duplicates across sessions (copy/duplicate session) collapse on the
same key, which is the intent.

## Scan context and capability

```dart
final class UsageScanContext {
  final Filesystem fs;
  final CliTool cli;
  final Map<String, String> env;      // CODEX_HOME / OPENCODE_DB / …
  final List<String> transcriptRoots; // same list history uses
  final String taskId;                // TeamPilot seat task id (client-pinned CLIs)
  final String nativeSessionId;       // persisted native id, '' when absent
  final String sessionId;
  final String memberId;
  final String teamId;
  final String workingDirectory;
  final String appDataRoot;
}

final class SessionUsageSource {
  final String id;                    // stable cursor key
  final String path;
  final UsageSourceKind kind;
  final String sessionId;
  final String memberId;
  final String teamId;
}

final class UsageCursor {
  final int? byteOffset;
  final int? mtimeMs;
  final int? size;
  final int? tailFingerprint;         // 64-bit hash of bytes before offset
  final int? lineOffset;              // legacy / row fallback
  final String? storeToken;           // SQLite row token
}

final class UsageScanResult {
  final List<SessionUsageEvent> events;
  final UsageCursor nextCursor;
  final bool partialTail;             // held back, cursor not advanced
  final int skippedLines;
}

abstract interface class SessionUsageCapability implements CliCapability {
  Future<List<SessionUsageSource>> discoverUsageSources(UsageScanContext ctx);

  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  });
}
```

The capability owns format knowledge and cursor semantics. The sync service
owns enumeration, ordering, locking, and error collection.

### Source ownership

`transcriptRoots` is the layered search list, not an ownership claim. App-level
and workspace-level roots can be shared by many sessions. A capability must
only return files that belong to the current seat:

- Claude: a file named `{id}.jsonl`, or a path under `{id}/` (subagent /
  workflow sidecars), where `{id}` is `nativeSessionId` when present and
  `taskId` otherwise. Probe the same roots history uses.
- Codex: every rollout under the seat's `CODEX_HOME` belongs to that seat,
  including subagent rollouts; the home itself is session-isolated.
- OpenCode: read all assistant rows in the per-seat `OPENCODE_DB`; subagent
  sessions share that DB and their tokens belong to the seat. Do not filter by
  `ses_*` when the DB is already seat-scoped.

Attribution fields (`sessionId`, `memberId`, `teamId`) come from
`UsageScanContext`, never from the file path.

## Target enumeration

`UsageScanTargetProvider` turns TeamPilot's session store into scan contexts:

```dart
abstract interface class UsageScanTargetProvider {
  Future<List<UsageScanContext>> targets();
}
```

Production implementation:

1. `SessionRepository.loadSessions()` (all workspaces).
2. Skip archived/deleted sessions? Keep archived: their history is still
   real usage. Deleted sessions have no directory and yield no sources.
3. Simple session: one target, `cli = session.cli ?? CliTool.claude`,
   `memberId = ''`.
4. Team session: resolve `TeamProfile` through the injected
   `Future<TeamProfile?> Function(String teamId)`; expand
   `sessionRosterMembers(session, team)` and read each binding's `cli`.
   Fallback order for legacy rows: binding `cli` → roster member `cli` →
   `session.cli`; skip only when all are null.
5. Build the context with `SessionHistoryContextBuilder` (which already
   resolves `taskId`, persisted native id, env, and roots) and add
   `appDataRoot`.

The provider is the only place that knows about sessions and rosters. The
store and parsers stay session-agnostic.

## Per-CLI extraction

### Claude Code

- Source: `{root}/projects/**/*.jsonl` under every `transcriptRoot`, filtered to
  the seat ids (`{nativeSessionId}.jsonl` / `{taskId}.jsonl`, plus their
  `{id}/` subagent and workflow children). Deduplicate identical paths across
  layered roots.
- Line filter: `type == "assistant"` and `message.usage` present.
- Fields: `input_tokens`, `output_tokens`, `cache_read_input_tokens`,
  `cache_creation_input_tokens`,
  `cache_creation.ephemeral_1h_input_tokens`.
- `isFinal = message.stop_reason != null`.
- Import when any of the four counters is greater than zero. A
  `message_start`-only workflow request still bills input/cache.
- Duplicate `message.id` inside a file: keep `isFinal` over non-final,
  otherwise the larger `output_tokens`. The store's upsert applies the same
  rule across incremental scans.
- Cursor: byte offset + mtime + size + tail fingerprint. Advance only past a
  complete line. On truncation or fingerprint mismatch, pin to EOF and do not
  replay (prevents double-counting already rolled-up history).

### Codex

- Source: `{CODEX_HOME}/sessions/**/rollout-*.jsonl`.
- Usage events carry cumulative `total_usage` / `token_count` snapshots.
  Convert each snapshot to a delta against the prior snapshot in the same
  thread; the first snapshot is the baseline.
- Fields: `input_tokens`, `cached_input_tokens` (fallback
  `cache_read_input_tokens`), `cache_write_input_tokens`, `output_tokens`.
- `inputSemantics = total`; clamp `cached <= input` and
  `cacheWrite <= input - cached`.
- `requestId = codex:{threadId}:{lineOffset}`; the absolute offset of the
  `token_count` line is stable in an append-only rollout.
- `isFinal = true` (a cumulative snapshot is the settled value at that point).
- Cursor: byte offset + mtime + size + the last cumulative counters in
  `storeToken`. Codex appends; re-parsing from the cursor is enough. The
  baseline lets a scan that only sees `total_token_usage` emit the correct
  delta across runs. Duplicate deltas are harmless because the request ids are
  stable and upsert is idempotent.

### OpenCode

- Source: `{OPENCODE_DB}` (or `{dir}/opencode.db`). Reuse
  `resolveOpencodeSqliteReadPath`, which copies DB + WAL to a temp file when
  the home plane is remote.
- Read assistant messages from `session_message` (fall back to `message` for
  the legacy layout), including `tokens` and `model`.
- Fields: `tokens.input`, `tokens.output`, `tokens.reasoning`,
  `tokens.cache.read`, `tokens.cache.write`.
- `outputTokens = output + reasoning` (reasoning is billed as output).
- `inputSemantics = fresh`; `isFinal = true`.
- `requestId = opencode:{messageId}`; a later row with the same id replaces
  the earlier one when its output is larger (streaming turn settled).
- Cursor: `storeToken` = `{maxSeq}:{maxUpdatedAt}` (or the highest message
  id when those columns are absent). On token regression, fall back to a full
  read and re-upsert.

## Store

Layout under the current home plane's app data root:

```text
<appDataRoot>/usage/events.jsonl
<appDataRoot>/usage/cursors.json
```

`events.jsonl` is append-only. Each line:

```json
{"rev": 0, "event": { ... }}
```

`UsageStore`:

```dart
abstract interface class UsageStore {
  Future<UsageAppendResult> upsert(Iterable<SessionUsageEvent> events);
  Future<List<SessionUsageEvent>> readLatest();
}

final class UsageAppendResult {
  final int inserted;
  final int updated;
  final int skipped;
}
```

Upsert rules (generic, no CLI switch):

1. New `requestId` → insert, `rev = 0`.
2. Existing, `incoming.isFinal && !existing.isFinal` → append correction.
3. Same finality and `incoming.outputTokens > existing.outputTokens` → append
   correction.
4. Otherwise skip.
5. A correction line reuses the same `requestId` with `rev + 1`. Readers keep
   the highest `rev` per id.

`JsonUsageStore` keeps a `Map<String, _Record>` index in memory, loaded once
from `events.jsonl` on first use. Append uses `Filesystem.appendString`; the
index is updated only after the append succeeds. A partial last line is
ignored on load and will be rewritten by the next sync (same ids, upsert
idempotent).

Why JSONL instead of SQLite: the app data root may be on the SSH home plane
and `sqlite3` cannot open SFTP paths. Existing TeamPilot repositories already
use `Filesystem` JSON. `UsageStore` is a port, so a local SQLite
implementation can replace it later if volume justifies it.

### Cursors

```text
cursors.json = { "<source.id>": { "byteOffset": …, "mtimeMs": …, … } }
```

`UsageCursorStore` reads/writes the whole map with `atomicWrite`. Writes are
serialized with `LockPool` keyed by the cursors path.

Order in `SessionUsageSyncService`:

1. scan source from cursor;
2. `store.upsert(events)`;
3. `cursors.save(source.id, nextCursor)`.

A crash between 2 and 3 re-reads the source; upsert is idempotent. A crash
between 1 and 2 loses nothing because the cursor was not advanced.

## Sync service

```dart
final class SessionUsageSyncService {
  SessionUsageSyncService({
    required UsageScanTargetProvider targets,
    required UsageStore store,
    required UsageCursorStore cursors,
    required CliToolRegistry registry,
  });

  Future<UsageSyncResult> syncAll();
}

final class UsageSyncResult {
  final int targetsScanned;
  final int sourcesScanned;
  final int inserted;
  final int updated;
  final int skipped;
  final List<UsageSyncError> errors;
}
```

`syncAll()`:

1. Acquire a process-wide sync lock (same pattern as
   `session_sync_mutex`).
2. `targets()`.
3. For each target, `registry.capability<SessionUsageCapability>(ctx.cli)`.
   Missing capability → skip silently.
4. `discoverUsageSources(ctx)`, then scan each source from its cursor.
5. Upsert, save cursor, accumulate counts.
6. Catch per-source errors into `errors`; never abort the whole run.

No timer in this slice. The UI calls `syncAll()` only from the manual sync
button; app startup reads cached events without scanning.

## UI

### Entry and navigation

- `HomeGlobalView.usage` is a first-class workspace-home view, rendered by
  `home_workspace_global_section.dart`.
- The sidebar row is added in `home_workspace_sidebar.dart` next to the
  provider `余额与用量` row, labeled `sessionUsageNav` ("Token 用量").
- `homeLocation` builds `/home-v2?global=usage`; `app_router.dart` restores it
  like the other global views. No new route.
- The page is embedded (`WorkspacePane`), not a dialog and not a settings
  section.

### Page

```text
header:  Token 用量 / 按 TeamPilot 会话归属统计  ·  last sync · 同步
notice:  per-source sync failures (dismissible, data stays visible)
toolbar: 今天 | 近 7 天 | 近 30 天 | 全部    CLI: 全部 | Claude | Codex | OpenCode
cards:   总 Token | 输入 Token | 输出 Token | 缓存读取
         subtexts: requests/sessions, share, cache hit rate/write, sparkline
chart:   近 7 天按 CLI 堆叠 (fixed 7-day context; selected CLI highlighted)
side:    CLI 分布 (share bars, cache-read share)
table:   group by 会话 / 成员 / 模型 / CLI, table-local search, share bar
footer:  showing N / total · JSONL 只读 · 手动同步
```

States: `initial`, `loading`, `ready`, `empty`, `error`. A failed sync keeps
the previously loaded events visible and shows a localized banner; a single
source failure does not blank the page. The sync button is disabled while a
sync is in flight.

Responsive behavior follows the existing workspace shell: the sidebar
collapses to icons/drawer on narrow widths, stats go 2x2 then 1 column, and the
detail table scrolls horizontally.

### Data flow

```dart
final class SessionUsageServices {
  Future<UsageSyncResult> syncAll();
  Future<List<SessionUsageEvent>> loadEvents();
  UsageAttribution loadAttribution(List<AppSession> sessions,
      List<TeamProfile> teams);
}
```

- `client/lib/app/session_usage_services.dart` is the app-layer composition
  factory. It builds `JsonUsageStore`, `JsonUsageCursorStore`,
  `TeamPilotUsageScanTargetProvider`, and `SessionUsageSyncService` from
  `HomeStorage`, `SessionRepository`, `LaunchProfileRepository`, and
  `CliToolRegistry`, and exposes `syncAll`/`loadEvents`.
- `SessionUsageCubit` is app-scoped and constructed with the home plane (same
  lifetime as `ManagedProviderUsageCubit`). It loads cached events on creation
  and exposes filters (`range`, `cli`, `groupBy`, `query`), summary, groups,
  sync state, and sync errors.
- `load()` only reads JSONL. It never scans CLI transcripts.
- `sync()` calls `SessionUsageSyncService.syncAll()` then reloads. The sync
  result's errors are retained; a failed source does not clear data.
- Attribution is resolved in the UI layer from `SessionRepository` and
  `LaunchProfileRepository` (team/member names via
  `sessionRosterMembers`); missing names fall back to ids. This does not
  change the foundation event model.

### Aggregation

Pure functions in `services/usage/usage_aggregator.dart`:

- `freshInput = inputSemantics == fresh
    ? inputTokens
    : max(0, inputTokens - cacheReadTokens - cacheCreationTokens)`.
- `total = freshInput + outputTokens + cacheReadTokens +
  cacheCreationTokens`; cache is never double-counted.
- `requests` = latest events in range; `sessions` = distinct `sessionId`.
- Range uses `timestampMs`; CLI filter uses `cli`; grouping is
  session/member/model/CLI. Search applies to table rows only, not to summary
  cards.
- Partial (`isFinal == false`) events participate only until a final
  correction supersedes them; the store already returns one latest event per
  `requestId`.
- No cost/pricing is computed. `costMicroUsd` is not displayed in this slice.

### L10n and errors

- Add keys only to `client/lib/l10n/app_en.arb` and `app_zh.arb`.
- User-visible strings go through l10n; diagnostics go through `AppLogger`.
- Sync errors show the affected CLI/source count and a retry action; details
  stay in the cubit state for diagnostics.
- The empty state offers a manual sync and a filter reset.

## Error handling

| Case | Behavior |
|------|----------|
| Missing session/runtime directory | No sources; not an error |
| Missing/unreadable transcript file | Skip source; record error |
| Corrupt JSONL line | Skip line; `skippedLines++`; continue |
| Partial last line | Hold cursor; re-read next run |
| Truncated/rewritten JSONL | Fingerprint mismatch → pin cursor to EOF; no replay |
| OpenCode schema mismatch | Whole source error; keep prior cursor |
| Store append failure | Do not save cursor; next run retries |
| Capability throws | Record error for that source; continue others |

## Testing

New tests under `client/test/services/usage/` and per-CLI capability tests.
Use `InMemoryFilesystem` and `test/support/opencode_v2_sqlite.dart` where
possible.

1. **Model**: serialization round-trip, equality, request-id formats.
2. **JsonUsageStore**: insert, correction on final, correction on larger
   output, skipped older snapshot, latest-read wins, partial line ignored.
3. **JsonUsageCursorStore**: round-trip, atomic write, concurrent save lock.
4. **Claude**: usage fields, `isFinal` from `stop_reason`, duplicate id
   selection, message-start-only import, 1h cache subset, zero-usage skip,
   partial tail held, truncation pin.
5. **Codex**: first snapshot, second delta, continuation baseline, repeated
   snapshot, cached clamp, total semantics.
6. **OpenCode**: fresh input, reasoning added to output, cache read/write,
   upsert on settled message, cursor advance.
7. **Sync service**: fake target provider + fake capability + fake store;
   verify capability selection, cursor advance, idempotent re-run, error
   isolation.
8. **Target provider**: Simple session, mixed seat, member without CLI,
   missing team profile (skip, no throw).
9. **Aggregator**: fresh/total normalization, no double-counted cache, range
   and CLI filters, group-by session/member/model/CLI, table-local search,
   empty rows.
10. **Cubit**: cached load, manual sync/reload, sync errors retained, filter
    changes without rescanning.
11. **Page/widget**: empty state, summary cards, group tabs, CLI/range filters,
    sync button disabled while running, error banner.
12. **Navigation**: sidebar row and `/home-v2?global=usage` deep link.

Run via `cd client && dart run tool/run_tests.dart <paths>`, never
`flutter test` directly.

## Risks

- **Session enumeration cost**: TeamPilot may have many sessions; remote reads
  go through SFTP. Bound concurrency (same 16-read cap `SessionRepositoryFs`
  uses) and scan on demand only in this slice.
- **Duplicate transcripts across layers**: symlinked/copied config trees can
  expose the same file. Deduplicate by canonical `source.id` and by
  `requestId`.
- **Codex delta stability**: thread id from filename, delta ordinal from a
  deterministic replay. If Codex rewrites a rollout, the cursor's truncation
  path handles it.
- **OpenCode schema drift**: `session_message` vs legacy `message`; feature
  detect columns, do not assume one layout.
- **Claude non-final snapshots**: the upsert policy intentionally keeps a
  settled `isFinal` record over a larger partial one, matching cc-switch.
- **UI attribution drift**: sessions/teams can be deleted while cached usage
  remains. The aggregator must fall back to ids rather than throw; cached
  events survive attribution changes.
- **Remote JSONL reads**: the page loads the cached JSONL only; manual sync
  may still incur SFTP latency. Keep the sync button cancellable by timeout at
  the source level and never block the initial paint.

## Follow-ups

1. Periodic sync + manual refresh trigger.
2. Cost engine and pricing table.
3. Global-roots mode for CLI sessions started outside TeamPilot.
4. Per-session header meter and per-message inline usage.
5. ACP `usage_update` live context window and cost.
6. Optional local SQLite store behind the same port.
7. Cache-write column and model/provider cost breakdown in the UI.

# Agent CLI Usage Tracking (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Record per-request token usage for TeamPilot-launched Claude, Codex, and OpenCode sessions on local and SSH home planes, using per-session transcript scanning, a JSONL usage store, and incremental cursors. No UI, scheduler, pricing, or proxy in this slice.

**Architecture:** One `SessionUsageCapability` per CLI discovers and parses that CLI's transcripts under the per-seat `CONFIG_DIR` / `CODEX_HOME` / `OPENCODE_DB`. A `SessionUsageSyncService` enumerates seats through `SessionHistoryContextBuilder`, calls the capability, upserts events into `usage/events.jsonl`, and advances `usage/cursors.json`. Everything goes through `Filesystem`, so it works over SFTP.

**Tech stack:** Dart 3 / Flutter, `package:equatable`, `package:synchronized`, `package:sqlite3`, existing `Filesystem` abstraction, `InMemoryFilesystem` test fake, `dart run tool/run_tests.dart`.

**Design spec:** `docs/superpowers/specs/2026-10-26-agent-cli-usage-tracking-design.md`

---

## Before you start

- Work in `/home/hhoa/git/hhoa/teampilot` on the current branch. Do not create a worktree unless the user asks.
- The checkout may contain unrelated user changes. Never run `git add -A` or `git commit -a`. Every commit below uses explicit paths or `git commit -- <paths>`.
- Run Dart tests only from `client/` with `dart run tool/run_tests.dart ...`. Never call `flutter test` directly.
- The inner loop is `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`. Run it after each task; run the task's test file first.

```bash
cd /home/hhoa/git/hhoa/teampilot
git status --short
```

Expected: you see the user's pre-existing modifications (l10n/chat/floating-workspace files). Leave them alone.

---

## File map

| File | Action | Responsibility |
|------|--------|----------------|
| `client/lib/models/session_usage.dart` | create | Event model, semantics enum |
| `client/lib/services/cli/registry/capabilities/session_usage_capability.dart` | create | Capability port, scan context/source/cursor/result |
| `client/lib/services/storage/app_paths.dart` | modify | `usage/` paths |
| `client/lib/services/usage/jsonl_usage_cursor_reader.dart` | create | Complete-line byte cursor + fingerprint |
| `client/lib/services/usage/usage_store.dart` | create | Store port + append result |
| `client/lib/services/usage/usage_cursor_store.dart` | create | Cursor store port |
| `client/lib/services/usage/json_usage_store.dart` | create | JSONL store with upsert/rev |
| `client/lib/services/usage/json_usage_cursor_store.dart` | create | Atomic JSON cursor map |
| `client/lib/services/usage/usage_scan_target_provider.dart` | create | Target port |
| `client/lib/services/usage/team_pilot_usage_scan_target_provider.dart` | create | Sessions → scan contexts |
| `client/lib/services/usage/session_usage_sync_service.dart` | create | Locked orchestration + errors |
| `client/lib/app/session_usage_services.dart` | create | Composition factory for app wiring |
| `client/lib/services/cli/claude/capabilities/usage/session_usage.dart` | create | Claude JSONL extraction |
| `client/lib/services/cli/codex/capabilities/usage/session_usage.dart` | create | Codex rollout extraction |
| `client/lib/services/cli/opencode/capabilities/usage/session_usage.dart` | create | OpenCode SQLite extraction |
| `client/lib/services/cli/{claude,codex,opencode}/*_tool.dart` | modify | Register the capability |
| `client/test/models/session_usage_test.dart` | create | Model round-trip |
| `client/test/services/usage/jsonl_usage_cursor_reader_test.dart` | create | Cursor/partial/truncation |
| `client/test/services/usage/json_usage_store_test.dart` | create | Upsert/rev/idempotency |
| `client/test/services/usage/json_usage_cursor_store_test.dart` | create | Cursor persistence |
| `client/test/services/usage/session_usage_sync_service_test.dart` | create | Locked orchestration + errors |
| `client/test/services/usage/team_pilot_usage_scan_target_provider_test.dart` | create | Simple/mixed/native targets |
| `client/test/services/cli/registry/capabilities/usage/claude_session_usage_test.dart` | create | Claude parsing |
| `client/test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart` | create | Codex deltas/baseline |
| `client/test/services/cli/registry/capabilities/usage/opencode_session_usage_test.dart` | create | SQLite parsing |

All new hand-written files stay well under the repo's size limits. If a file grows past ~400 lines, split by CLI/layout, not by helper type.

---

## Task 1: Event model, capability port, usage paths

**Files:**
- Create: `client/lib/models/session_usage.dart`
- Create: `client/lib/services/cli/registry/capabilities/session_usage_capability.dart`
- Modify: `client/lib/services/storage/app_paths.dart`
- Create: `client/test/models/session_usage_test.dart`

- [x] **Step 1: Write the failing model test**

Create `client/test/models/session_usage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('round-trips every field', () {
    const event = SessionUsageEvent(
      requestId: 'claude:msg_1',
      cli: CliTool.claude,
      model: 'claude-sonnet-4',
      inputTokens: 100,
      outputTokens: 40,
      cacheReadTokens: 25,
      cacheCreationTokens: 10,
      cacheCreation1hTokens: 5,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: 1720612802000,
      sessionId: 's1',
      memberId: 'dev-0',
      teamId: 'team1',
      isFinal: true,
      costMicroUsd: 1234,
    );

    final decoded = SessionUsageEvent.fromJson(event.toJson());

    expect(decoded, event);
    expect(decoded.toJson(), event.toJson());
    expect(decoded.freshInputTokens, 100);
    expect(decoded.hasBillableTokens, isTrue);
  });

  test('total semantics subtracts cache from fresh input', () {
    const event = SessionUsageEvent(
      requestId: 'codex:t:1',
      cli: CliTool.codex,
      model: 'gpt-5',
      inputTokens: 100,
      outputTokens: 10,
      cacheReadTokens: 30,
      cacheCreationTokens: 5,
      inputSemantics: UsageInputSemantics.total,
      timestampMs: 1,
      sessionId: 's1',
    );

    expect(event.freshInputTokens, 65);
  });

  test('zero-token event is not billable', () {
    expect(
      const SessionUsageEvent(
        requestId: 'x',
        cli: CliTool.claude,
        model: '',
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        inputSemantics: UsageInputSemantics.fresh,
        timestampMs: 0,
        sessionId: '',
      ).hasBillableTokens,
      isFalse,
    );
  });
}
```

- [x] **Step 2: Run it and confirm it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/models/session_usage_test.dart
```

Expected: compile failure, `session_usage.dart` not found.

- [x] **Step 3: Implement the model**

Create `client/lib/models/session_usage.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'team_config.dart';

/// Wire meaning of [SessionUsageEvent.inputTokens].
///
/// - [fresh]: input excludes cache (Claude, OpenCode).
/// - [total]: input includes cache read/write (Codex, Gemini, Grok).
enum UsageInputSemantics {
  fresh('fresh'),
  total('total');

  const UsageInputSemantics(this.value);

  final String value;

  static UsageInputSemantics fromJson(Object? raw) =>
      tryParse(raw?.toString()) ?? fresh;

  static UsageInputSemantics? tryParse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final value in values) {
      if (value.value == normalized) return value;
    }
    return null;
  }
}

@immutable
class SessionUsageEvent extends Equatable {
  const SessionUsageEvent({
    required this.requestId,
    required this.cli,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheCreationTokens,
    this.cacheCreation1hTokens = 0,
    required this.inputSemantics,
    required this.timestampMs,
    required this.sessionId,
    this.memberId = '',
    this.teamId = '',
    this.isFinal = true,
    this.costMicroUsd,
  });

  /// CLI-scoped dedup key. See the design spec for the per-CLI formats.
  final String requestId;
  final CliTool cli;
  final String model;

  /// Tokens as reported by the CLI. Never rewritten.
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int cacheCreation1hTokens;
  final UsageInputSemantics inputSemantics;

  final int timestampMs;
  final String sessionId;
  final String memberId;
  final String teamId;

  /// True when the CLI reported a settled value; false for a streaming
  /// `message_start`-style snapshot that may still grow.
  final bool isFinal;

  /// Only set when a CLI reports cost itself; no pricing table here.
  final int? costMicroUsd;

  bool get hasBillableTokens =>
      inputTokens > 0 ||
      outputTokens > 0 ||
      cacheReadTokens > 0 ||
      cacheCreationTokens > 0;

  /// Input excluding cache, for aggregation across mixed semantics.
  int get freshInputTokens {
    if (inputSemantics == UsageInputSemantics.fresh) return inputTokens;
    return (inputTokens - cacheReadTokens - cacheCreationTokens).clamp(
      0,
      inputTokens,
    );
  }

  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'cli': cli.value,
    'model': model,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheCreationTokens': cacheCreationTokens,
    'cacheCreation1hTokens': cacheCreation1hTokens,
    'inputSemantics': inputSemantics.value,
    'timestampMs': timestampMs,
    'sessionId': sessionId,
    'memberId': memberId,
    'teamId': teamId,
    'isFinal': isFinal,
    if (costMicroUsd != null) 'costMicroUsd': costMicroUsd,
  };

  factory SessionUsageEvent.fromJson(Map<String, Object?> json) {
    return SessionUsageEvent(
      requestId: '${json['requestId'] ?? ''}',
      cli: CliTool.tryParse(json['cli']?.toString()) ?? CliTool.claude,
      model: '${json['model'] ?? ''}',
      inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
      cacheCreationTokens: (json['cacheCreationTokens'] as num?)?.toInt() ?? 0,
      cacheCreation1hTokens:
          (json['cacheCreation1hTokens'] as num?)?.toInt() ?? 0,
      inputSemantics: UsageInputSemantics.fromJson(json['inputSemantics']),
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
      sessionId: '${json['sessionId'] ?? ''}',
      memberId: '${json['memberId'] ?? ''}',
      teamId: '${json['teamId'] ?? ''}',
      isFinal: json['isFinal'] != false,
      costMicroUsd: (json['costMicroUsd'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [
    requestId,
    cli,
    model,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheCreationTokens,
    cacheCreation1hTokens,
    inputSemantics,
    timestampMs,
    sessionId,
    memberId,
    teamId,
    isFinal,
    costMicroUsd,
  ];
}
```

- [x] **Step 4: Implement the capability port**

Create `client/lib/services/cli/registry/capabilities/session_usage_capability.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../io/filesystem.dart';
import '../../../../models/session_usage.dart';
import '../../../../models/team_config.dart';
import '../cli_capability.dart';

@immutable
class UsageScanContext {
  const UsageScanContext({
    required this.fs,
    required this.cli,
    required this.env,
    required this.transcriptRoots,
    required this.taskId,
    required this.nativeSessionId,
    required this.sessionId,
    required this.memberId,
    required this.teamId,
    required this.workingDirectory,
    required this.appDataRoot,
  });

  final Filesystem fs;
  final CliTool cli;
  final Map<String, String> env;
  final List<String> transcriptRoots;

  /// TeamPilot seat task id (pinned native id for client-pinned CLIs).
  final String taskId;

  /// Persisted CLI-native session id, or `''` before capture.
  final String nativeSessionId;

  final String sessionId;
  final String memberId;
  final String teamId;
  final String workingDirectory;
  final String appDataRoot;
}

enum UsageSourceKind {
  jsonl('jsonl'),
  sqlite('sqlite');

  const UsageSourceKind(this.value);

  final String value;

  static UsageSourceKind fromJson(Object? raw) {
    final normalized = raw?.toString();
    for (final value in values) {
      if (value.value == normalized) return value;
    }
    return jsonl;
  }
}

@immutable
class SessionUsageSource extends Equatable {
  const SessionUsageSource({
    required this.id,
    required this.path,
    required this.kind,
    required this.sessionId,
    required this.memberId,
    required this.teamId,
  });

  /// Stable cursor key. Include the file/DB path, not just the session id.
  final String id;
  final String path;
  final UsageSourceKind kind;
  final String sessionId;
  final String memberId;
  final String teamId;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'kind': kind.value,
    'sessionId': sessionId,
    'memberId': memberId,
    'teamId': teamId,
  };

  @override
  List<Object?> get props => [id, path, kind, sessionId, memberId, teamId];
}

@immutable
class UsageCursor extends Equatable {
  const UsageCursor({
    this.byteOffset,
    this.mtimeMs,
    this.size,
    this.tailFingerprint,
    this.lineOffset,
    this.storeToken,
  });

  static const empty = UsageCursor();

  final int? byteOffset;
  final int? mtimeMs;
  final int? size;

  /// 32-bit FNV-1a of up to 4 KiB before [byteOffset], for rewrite detection.
  final int? tailFingerprint;

  /// Complete lines consumed so far (JSONL only).
  final int? lineOffset;

  /// Capability-specific state (OpenCode snapshot token, Codex baseline).
  final String? storeToken;

  bool get isEmpty =>
      byteOffset == null && lineOffset == null && storeToken == null;

  Map<String, Object?> toJson() => {
    if (byteOffset != null) 'byteOffset': byteOffset,
    if (mtimeMs != null) 'mtimeMs': mtimeMs,
    if (size != null) 'size': size,
    if (tailFingerprint != null) 'tailFingerprint': tailFingerprint,
    if (lineOffset != null) 'lineOffset': lineOffset,
    if (storeToken != null) 'storeToken': storeToken,
  };

  factory UsageCursor.fromJson(Map<String, Object?> json) => UsageCursor(
    byteOffset: (json['byteOffset'] as num?)?.toInt(),
    mtimeMs: (json['mtimeMs'] as num?)?.toInt(),
    size: (json['size'] as num?)?.toInt(),
    tailFingerprint: (json['tailFingerprint'] as num?)?.toInt(),
    lineOffset: (json['lineOffset'] as num?)?.toInt(),
    storeToken: json['storeToken']?.toString(),
  );

  @override
  List<Object?> get props => [
    byteOffset,
    mtimeMs,
    size,
    tailFingerprint,
    lineOffset,
    storeToken,
  ];
}

@immutable
class UsageScanResult {
  const UsageScanResult({
    required this.events,
    required this.nextCursor,
    this.partialTail = false,
    this.skippedLines = 0,
  });

  final List<SessionUsageEvent> events;
  final UsageCursor nextCursor;

  /// A trailing incomplete line was held back; [nextCursor] stops before it.
  final bool partialTail;
  final int skippedLines;
}

/// Implemented by each CLI definition that can account token usage.
abstract interface class SessionUsageCapability implements CliCapability {
  Future<List<SessionUsageSource>> discoverUsageSources(UsageScanContext ctx);

  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  });
}
```

- [x] **Step 5: Add usage paths**

In `client/lib/services/storage/app_paths.dart`, add these getters next to the provider paths (after `managedProviderUsageCacheFile`):

```dart
  /// Agent CLI token usage, stored on the current home plane.
  String get usageDir => _ctx.join(basePath, 'usage');

  String get usageEventsFile => _ctx.join(usageDir, 'events.jsonl');

  String get usageCursorsFile => _ctx.join(usageDir, 'cursors.json');
```

- [x] **Step 6: Run the test and the analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/models/session_usage_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 3 tests pass; analyzer clean for the new files.

- [x] **Step 7: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/models/session_usage.dart \
  client/lib/services/cli/registry/capabilities/session_usage_capability.dart \
  client/lib/services/storage/app_paths.dart \
  client/test/models/session_usage_test.dart
git commit -m "feat(usage): add usage event model and capability port" -- \
  client/lib/models/session_usage.dart \
  client/lib/services/cli/registry/capabilities/session_usage_capability.dart \
  client/lib/services/storage/app_paths.dart \
  client/test/models/session_usage_test.dart
```

---

## Task 2: Incremental JSONL reader

**Files:**
- Create: `client/lib/services/usage/jsonl_usage_cursor_reader.dart`
- Create: `client/test/services/usage/jsonl_usage_cursor_reader_test.dart`

- [x] **Step 1: Write the failing reader tests**

Create `client/test/services/usage/jsonl_usage_cursor_reader_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/usage/jsonl_usage_cursor_reader.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  });

  // ASCII only: InMemoryFilesystem stores text as UTF-16 code units, which is
  // byte-identical to UTF-8 for these fixtures.
  Future<void> write(String text) => fs.writeString('/tp/a.jsonl', text);

  test('reads only complete lines and holds the partial tail', () async {
    await write('one\ntwo\npart');

    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );

    expect(first.lines, ['one', 'two']);
    expect(first.lineOffsets, [0, 4]);
    expect(first.partialTail, isTrue);
    expect(first.nextCursor.byteOffset, 8);
    expect(first.nextCursor.tailFingerprint, isNotNull);

    await fs.appendString('/tp/a.jsonl', 'ial\n');
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.lines, ['partial']);
    expect(second.lineOffsets, [8]);
    expect(second.partialTail, isFalse);
    expect(second.nextCursor.byteOffset, 16);
  });

  test('returns nothing when the file has not grown', () async {
    await write('one\n');
    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.lines, isEmpty);
    expect(second.partialTail, isFalse);
    expect(second.nextCursor.byteOffset, first.nextCursor.byteOffset);
  });

  test('pins to EOF when a rewrite changes the tail fingerprint', () async {
    await write('aaaa\n');
    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );

    await write('bbbb\n');
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.pinnedToEof, isTrue);
    expect(second.lines, isEmpty);
    expect(second.nextCursor.byteOffset, 5);
  });

  test('pins to EOF when the file shrinks below the cursor', () async {
    await write('one\ntwo\n');
    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );

    await write('x');
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.pinnedToEof, isTrue);
    expect(second.lines, isEmpty);
    expect(second.nextCursor.byteOffset, 1);
  });
}
```

- [x] **Step 2: Run it and confirm it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/usage/jsonl_usage_cursor_reader_test.dart
```

Expected: compile failure, `jsonl_usage_cursor_reader.dart` not found.

- [x] **Step 3: Implement the reader**

Create `client/lib/services/usage/jsonl_usage_cursor_reader.dart`:

```dart
import 'dart:convert';

import '../cli/registry/capabilities/session_usage_capability.dart';
import '../io/filesystem.dart';

/// One incremental read of an append-only JSONL source.
class JsonlUsageWindow {
  const JsonlUsageWindow({
    required this.lines,
    required this.lineOffsets,
    required this.nextCursor,
    required this.partialTail,
    required this.pinnedToEof,
  });

  factory JsonlUsageWindow.empty(UsageCursor? cursor) => JsonlUsageWindow(
    lines: const [],
    lineOffsets: const [],
    nextCursor: cursor ?? UsageCursor.empty,
    partialTail: false,
    pinnedToEof: false,
  );

  /// Complete lines only; a trailing incomplete line is excluded.
  final List<String> lines;

  /// Absolute byte offset of each line start, parallel to [lines].
  final List<int> lineOffsets;

  final UsageCursor nextCursor;

  /// True when the source ended without a newline; the cursor stays before it.
  final bool partialTail;

  /// True when the file shrank or the tail fingerprint changed. No lines are
  /// returned and the cursor jumps to EOF to avoid replaying rolled-up history.
  final bool pinnedToEof;
}

const int _fingerprintWindow = 4096;
const int _fnvOffset = 0x811c9dc5;
const int _fnvPrime = 0x01000193;

/// Reads complete JSONL lines after [cursor].
///
/// Cursor contract:
/// - [UsageCursor.byteOffset] is the end of the last complete line.
/// - [UsageCursor.tailFingerprint] hashes up to 4 KiB before that offset.
/// - On truncation or a fingerprint mismatch, the caller gets no lines and a
///   cursor at EOF. That deliberately skips rewriting, which would double-count
///   already-imported history.
Future<JsonlUsageWindow> readJsonlUsageWindow({
  required Filesystem fs,
  required String path,
  required UsageCursor? cursor,
}) async {
  final stat = await fs.stat(path);
  if (!stat.isFile) return JsonlUsageWindow.empty(cursor);

  final size = stat.size ?? 0;
  final previous = cursor ?? UsageCursor.empty;
  final start = previous.byteOffset ?? 0;

  final truncated =
      start > size || (previous.size != null && size < previous.size!);
  if (truncated) {
    return _pinned(fs: fs, path: path, size: size, previous: previous);
  }

  if (start > 0 && previous.tailFingerprint != null) {
    final actual = await _tailFingerprint(fs, path, start);
    if (actual != previous.tailFingerprint) {
      return _pinned(fs: fs, path: path, size: size, previous: previous);
    }
  }

  final bytes = start < size
      ? await fs.readBytesRange(path, start, size - start) ?? const <int>[]
      : const <int>[];
  final lines = <String>[];
  final offsets = <int>[];
  var lineStart = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != 0x0a) continue;
    lines.add(utf8.decode(bytes.sublist(lineStart, i), allowMalformed: true));
    offsets.add(start + lineStart);
    lineStart = i + 1;
  }

  final committed = start + lineStart;
  final partialTail = lineStart < bytes.length;
  return JsonlUsageWindow(
    lines: lines,
    lineOffsets: offsets,
    nextCursor: UsageCursor(
      byteOffset: committed,
      mtimeMs: stat.mtime?.millisecondsSinceEpoch ?? 0,
      size: size,
      tailFingerprint: committed == 0
          ? null
          : await _tailFingerprint(fs, path, committed),
      lineOffset: (previous.lineOffset ?? 0) + lines.length,
    ),
    partialTail: partialTail,
    pinnedToEof: false,
  );
}

Future<JsonlUsageWindow> _pinned({
  required Filesystem fs,
  required String path,
  required int size,
  required UsageCursor previous,
}) async {
  return JsonlUsageWindow(
    lines: const [],
    lineOffsets: const [],
    nextCursor: UsageCursor(
      byteOffset: size,
      mtimeMs: 0,
      size: size,
      tailFingerprint: size == 0
          ? null
          : await _tailFingerprint(fs, path, size),
      lineOffset: previous.lineOffset,
      storeToken: previous.storeToken,
    ),
    partialTail: false,
    pinnedToEof: true,
  );
}

Future<int> _tailFingerprint(Filesystem fs, String path, int end) async {
  final start = end > _fingerprintWindow ? end - _fingerprintWindow : 0;
  final bytes =
      await fs.readBytesRange(path, start, end - start) ?? const <int>[];
  return _fnv1a32(bytes);
}

int _fnv1a32(List<int> bytes) {
  var hash = _fnvOffset;
  for (final byte in bytes) {
    hash ^= byte & 0xff;
    hash = (hash * _fnvPrime) & 0xffffffff;
  }
  return hash;
}
```

- [x] **Step 4: Run the tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/usage/jsonl_usage_cursor_reader_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: all 4 tests pass.

- [x] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/usage/jsonl_usage_cursor_reader.dart \
  client/test/services/usage/jsonl_usage_cursor_reader_test.dart
git commit -m "feat(usage): add incremental jsonl cursor reader" -- \
  client/lib/services/usage/jsonl_usage_cursor_reader.dart \
  client/test/services/usage/jsonl_usage_cursor_reader_test.dart
```

---

## Task 3: JSONL usage store and cursor store

**Files:**
- Create: `client/lib/services/usage/usage_store.dart`
- Create: `client/lib/services/usage/usage_cursor_store.dart`
- Create: `client/lib/services/usage/json_usage_store.dart`
- Create: `client/lib/services/usage/json_usage_cursor_store.dart`
- Create: `client/test/services/usage/json_usage_store_test.dart`
- Create: `client/test/services/usage/json_usage_cursor_store_test.dart`

- [x] **Step 1: Write the failing store tests**

Create `client/test/services/usage/json_usage_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/json_usage_store.dart';

import '../../support/in_memory_filesystem.dart';

SessionUsageEvent event({
  String id = 'claude:1',
  int output = 1,
  bool final_ = false,
  String session = 's1',
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: CliTool.claude,
    model: 'claude-sonnet-4',
    inputTokens: 10,
    outputTokens: output,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    inputSemantics: UsageInputSemantics.fresh,
    timestampMs: 1,
    sessionId: session,
    isFinal: final_,
  );
}

void main() {
  late InMemoryFilesystem fs;
  late JsonUsageStore store;

  setUp(() {
    fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    store = JsonUsageStore(fs: fs, filePath: '/tp/usage/events.jsonl');
  });

  test('inserts a new request', () async {
    final result = await store.upsert([event()]);

    expect(result.inserted, 1);
    expect(result.updated, 0);
    expect((await store.readLatest()).single.requestId, 'claude:1');
  });

  test('a final record replaces a non-final one', () async {
    await store.upsert([event(output: 1)]);
    final result = await store.upsert([event(output: 5, final_: true)]);

    expect(result.updated, 1);
    final latest = await store.readLatest();
    expect(latest.single.outputTokens, 5);
    expect(latest.single.isFinal, isTrue);
  });

  test('a larger output replaces an equally-final record', () async {
    await store.upsert([event(output: 5, final_: true)]);
    await store.upsert([event(output: 9, final_: true)]);

    expect((await store.readLatest()).single.outputTokens, 9);
  });

  test('a smaller or non-final snapshot is skipped', () async {
    await store.upsert([event(output: 9, final_: true)]);
    final result = await store.upsert([event(output: 2, final_: true)]);

    expect(result.skipped, 1);
    expect((await store.readLatest()).single.outputTokens, 9);
  });

  test('ignores a malformed trailing line on load and appends safely', () async {
    await fs.writeString('/tp/usage/events.jsonl', '{"rev":0,"event":{"requ');

    final result = await store.upsert([event()]);

    expect(result.inserted, 1);
    expect((await store.readLatest()).single.requestId, 'claude:1');
    expect(await fs.readString('/tp/usage/events.jsonl'), contains('\n{'));
  });

  test('zero-token events are not written', () async {
    final result = await store.upsert([
      SessionUsageEvent(
        requestId: 'zero',
        cli: CliTool.claude,
        model: '',
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        inputSemantics: UsageInputSemantics.fresh,
        timestampMs: 0,
        sessionId: 's1',
      ),
    ]);

    expect(result.skipped, 1);
    expect(await store.readLatest(), isEmpty);
  });
}
```

Create `client/test/services/usage/json_usage_cursor_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/usage/json_usage_cursor_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late JsonUsageCursorStore store;

  setUp(() {
    fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    store = JsonUsageCursorStore(fs: fs, filePath: '/tp/usage/cursors.json');
  });

  test('round-trips cursors', () async {
    await store.save(
      'src',
      const UsageCursor(
        byteOffset: 12,
        size: 20,
        tailFingerprint: 99,
        lineOffset: 3,
        storeToken: 'baseline',
      ),
    );

    final loaded = await store.read('src');
    expect(loaded?.byteOffset, 12);
    expect(loaded?.size, 20);
    expect(loaded?.tailFingerprint, 99);
    expect(loaded?.lineOffset, 3);
    expect(loaded?.storeToken, 'baseline');
    expect(await store.read('missing'), isNull);
  });

  test('removes one cursor and preserves others', () async {
    await store.save('a', const UsageCursor(byteOffset: 1));
    await store.save('b', const UsageCursor(byteOffset: 2));

    await store.remove('a');

    expect(await store.read('a'), isNull);
    expect((await store.read('b'))?.byteOffset, 2);
  });
}
```

- [x] **Step 2: Run them and confirm they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/usage/json_usage_store_test.dart
dart run tool/run_tests.dart test/services/usage/json_usage_cursor_store_test.dart
```

Expected: compile failures, the two implementation files are missing.

- [x] **Step 3: Implement the store ports**

Create `client/lib/services/usage/usage_store.dart`:

```dart
import '../../models/session_usage.dart';

class UsageAppendResult {
  const UsageAppendResult({
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
  });

  final int inserted;
  final int updated;
  final int skipped;
}

/// Persistence seam for usage events. Implementations must be idempotent per
/// [SessionUsageEvent.requestId].
abstract interface class UsageStore {
  Future<UsageAppendResult> upsert(Iterable<SessionUsageEvent> events);

  /// Latest revision per request id, oldest timestamp first.
  Future<List<SessionUsageEvent>> readLatest();
}
```

Create `client/lib/services/usage/usage_cursor_store.dart`:

```dart
import '../cli/registry/capabilities/session_usage_capability.dart';

/// Persistence seam for per-source scan progress.
abstract interface class UsageCursorStore {
  Future<UsageCursor?> read(String sourceId);

  Future<void> save(String sourceId, UsageCursor cursor);

  Future<void> remove(String sourceId);
}
```

- [x] **Step 4: Implement the JSONL store**

Create `client/lib/services/usage/json_usage_store.dart`:

```dart
import 'dart:convert';

import '../../models/session_usage.dart';
import '../../utils/lock_pool.dart';
import '../io/filesystem.dart';
import 'usage_store.dart';

final class _UsageRecord {
  const _UsageRecord(this.event, this.revision);

  final SessionUsageEvent event;
  final int revision;
}

/// Append-only JSONL store with an in-memory latest-revision index.
///
/// A correction is another line with the same `requestId` and a higher `rev`.
/// The file is never rewritten, so a crash can only leave an extra line, never
/// a torn earlier record. JSONL (not SQLite) keeps this usable on an SSH home
/// plane where `sqlite3` cannot open an SFTP path.
class JsonUsageStore implements UsageStore {
  JsonUsageStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;
  final LockPool _locks = LockPool();

  Map<String, _UsageRecord>? _index;
  bool _needsLeadingNewline = false;

  Future<Map<String, _UsageRecord>> _load() async {
    final cached = _index;
    if (cached != null) return cached;

    final raw = await _fs.readString(_path);
    final index = <String, _UsageRecord>{};
    _needsLeadingNewline = raw != null && raw.isNotEmpty && !raw.endsWith('\n');
    if (raw != null) {
      for (final line in const LineSplitter().convert(raw)) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) continue;
          final revision = (decoded['rev'] as num?)?.toInt() ?? 0;
          final eventRaw = decoded['event'];
          if (eventRaw is! Map) continue;
          final event = SessionUsageEvent.fromJson(
            Map<String, Object?>.from(eventRaw),
          );
          if (event.requestId.isEmpty) continue;
          final previous = index[event.requestId];
          if (previous == null || revision >= previous.revision) {
            index[event.requestId] = _UsageRecord(event, revision);
          }
        } on Object {
          continue;
        }
      }
    }
    _index = index;
    return index;
  }

  @override
  Future<UsageAppendResult> upsert(Iterable<SessionUsageEvent> events) {
    return _locks.synchronized(_path, () async {
      final current = await _load();
      final next = Map<String, _UsageRecord>.of(current);
      final buffer = StringBuffer();
      var inserted = 0;
      var updated = 0;
      var skipped = 0;

      if (_needsLeadingNewline && events.isNotEmpty) {
        buffer.write('\n');
      }

      for (final event in events) {
        if (event.requestId.isEmpty || !event.hasBillableTokens) {
          skipped++;
          continue;
        }
        final previous = next[event.requestId];
        if (previous == null) {
          next[event.requestId] = _UsageRecord(event, 0);
          buffer.writeln(jsonEncode({'rev': 0, 'event': event.toJson()}));
          inserted++;
          continue;
        }
        if (!_shouldReplace(previous.event, event)) {
          skipped++;
          continue;
        }
        final revision = previous.revision + 1;
        next[event.requestId] = _UsageRecord(event, revision);
        buffer.writeln(
          jsonEncode({'rev': revision, 'event': event.toJson()}),
        );
        updated++;
      }

      if (buffer.isNotEmpty) {
        try {
          await _fs.appendString(_path, buffer.toString());
        } on Object {
          // The in-memory index may no longer match a partially appended file.
          _index = null;
          rethrow;
        }
        _index = next;
        _needsLeadingNewline = false;
      }
      return UsageAppendResult(
        inserted: inserted,
        updated: updated,
        skipped: skipped,
      );
    });
  }

  static bool _shouldReplace(
    SessionUsageEvent previous,
    SessionUsageEvent incoming,
  ) {
    if (incoming.isFinal && !previous.isFinal) return true;
    if (!incoming.isFinal && previous.isFinal) return false;
    return incoming.outputTokens > previous.outputTokens;
  }

  @override
  Future<List<SessionUsageEvent>> readLatest() async {
    final index = await _load();
    final events = [for (final record in index.values) record.event];
    events.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return events;
  }
}
```

- [x] **Step 5: Implement the cursor store**

Create `client/lib/services/usage/json_usage_cursor_store.dart`:

```dart
import 'dart:convert';

import '../../utils/lock_pool.dart';
import '../cli/registry/capabilities/session_usage_capability.dart';
import '../io/filesystem.dart';
import 'usage_cursor_store.dart';

/// Whole-map JSON cursor file, written atomically.
class JsonUsageCursorStore implements UsageCursorStore {
  JsonUsageCursorStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;
  final LockPool _locks = LockPool();

  Map<String, UsageCursor>? _cache;

  Future<Map<String, UsageCursor>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _fs.readString(_path);
    final map = <String, UsageCursor>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! Map) continue;
            map['${entry.key}'] = UsageCursor.fromJson(
              Map<String, Object?>.from(value),
            );
          }
        }
      } on Object {
        // Corrupt cursor file: start clean. Events are upserted idempotently.
      }
    }
    _cache = map;
    return map;
  }

  @override
  Future<UsageCursor?> read(String sourceId) async {
    final map = await _load();
    return map[sourceId];
  }

  @override
  Future<void> save(String sourceId, UsageCursor cursor) {
    return _mutate((map) => map[sourceId] = cursor);
  }

  @override
  Future<void> remove(String sourceId) {
    return _mutate((map) => map.remove(sourceId));
  }

  Future<void> _mutate(void Function(Map<String, UsageCursor>) change) {
    return _locks.synchronized(_path, () async {
      final current = await _load();
      final next = Map<String, UsageCursor>.of(current);
      change(next);
      final encoded = {
        for (final entry in next.entries) entry.key: entry.value.toJson(),
      };
      await _fs.atomicWrite(
        _path,
        const JsonEncoder.withIndent('  ').convert(encoded),
      );
      _cache = next;
    });
  }
}
```

- [x] **Step 6: Run the tests and analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/usage/json_usage_store_test.dart test/services/usage/json_usage_cursor_store_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 8 tests pass (6 store + 2 cursor).

- [x] **Step 7: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/usage/usage_store.dart \
  client/lib/services/usage/usage_cursor_store.dart \
  client/lib/services/usage/json_usage_store.dart \
  client/lib/services/usage/json_usage_cursor_store.dart \
  client/test/services/usage/json_usage_store_test.dart \
  client/test/services/usage/json_usage_cursor_store_test.dart
git commit -m "feat(usage): add jsonl usage and cursor stores" -- \
  client/lib/services/usage/usage_store.dart \
  client/lib/services/usage/usage_cursor_store.dart \
  client/lib/services/usage/json_usage_store.dart \
  client/lib/services/usage/json_usage_cursor_store.dart \
  client/test/services/usage/json_usage_store_test.dart \
  client/test/services/usage/json_usage_cursor_store_test.dart
```

---

## Task 4: Sync service and target enumeration

**Files:**
- Create: `client/lib/services/usage/usage_scan_target_provider.dart`
- Create: `client/lib/services/usage/team_pilot_usage_scan_target_provider.dart`
- Create: `client/lib/services/usage/session_usage_sync_service.dart`
- Create: `client/test/services/usage/session_usage_sync_service_test.dart`
- Create: `client/test/services/usage/team_pilot_usage_scan_target_provider_test.dart`

- [x] **Step 1: Write the failing sync-service test**

Create `client/test/services/usage/session_usage_sync_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';
import 'package:teampilot/services/usage/usage_cursor_store.dart';
import 'package:teampilot/services/usage/usage_scan_target_provider.dart';
import 'package:teampilot/services/usage/usage_store.dart';

import '../../support/in_memory_filesystem.dart';

final class _FakeTargets implements UsageScanTargetProvider {
  _FakeTargets(this.contexts);

  final List<UsageScanContext> contexts;

  @override
  Future<List<UsageScanContext>> targets() async => contexts;
}

final class _FakeTool implements CliToolDefinition {
  _FakeTool(this.id, this.capabilities);

  @override
  final CliTool id;
  @override
  final List<CliCapability> capabilities;
  @override
  bool get isLaunchSupported => true;
}

final class _FakeCapability implements SessionUsageCapability {
  _FakeCapability({required this.sources, this.failOn});

  final List<SessionUsageSource> sources;
  final String? failOn;
  int scans = 0;

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async => sources;

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    scans++;
    if (source.id == failOn) throw StateError('boom');
    return UsageScanResult(
      events: [_event(source.id)],
      nextCursor: const UsageCursor(byteOffset: 7),
    );
  }
}

final class _FakeStore implements UsageStore {
  final events = <SessionUsageEvent>[];

  @override
  Future<UsageAppendResult> upsert(
    Iterable<SessionUsageEvent> next,
  ) async {
    final list = next.toList();
    events.addAll(list);
    return UsageAppendResult(inserted: list.length);
  }

  @override
  Future<List<SessionUsageEvent>> readLatest() async => List.of(events);
}

final class _FakeCursors implements UsageCursorStore {
  final saved = <String, UsageCursor>{};

  @override
  Future<UsageCursor?> read(String sourceId) async => saved[sourceId];

  @override
  Future<void> save(String sourceId, UsageCursor cursor) async {
    saved[sourceId] = cursor;
  }

  @override
  Future<void> remove(String sourceId) async {
    saved.remove(sourceId);
  }
}

SessionUsageEvent _event(String id) => SessionUsageEvent(
  requestId: 'claude:$id',
  cli: CliTool.claude,
  model: 'claude-sonnet-4',
  inputTokens: 10,
  outputTokens: 2,
  cacheReadTokens: 0,
  cacheCreationTokens: 0,
  inputSemantics: UsageInputSemantics.fresh,
  timestampMs: 1,
  sessionId: 's1',
);

UsageScanContext _ctx() => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.claude,
  env: const {},
  transcriptRoots: const [],
  taskId: 'task',
  nativeSessionId: 'native',
  sessionId: 's1',
  memberId: '',
  teamId: '',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

SessionUsageSource _source(String id) => SessionUsageSource(
  id: id,
  path: '/tp/$id.jsonl',
  kind: UsageSourceKind.jsonl,
  sessionId: 's1',
  memberId: '',
  teamId: '',
);

void main() {
  test('discovers, scans, stores, and advances cursors', () async {
    final capability = _FakeCapability(sources: [_source('a'), _source('b')]);
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final store = _FakeStore();
    final cursors = _FakeCursors();
    final service = SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: store,
      cursors: cursors,
      registry: registry,
    );

    final result = await service.syncAll();

    expect(result.targetsScanned, 1);
    expect(result.sourcesScanned, 2);
    expect(result.inserted, 2);
    expect(capability.scans, 2);
    expect(store.events, hasLength(2));
    expect(cursors.saved.keys, containsAll(['a', 'b']));
    expect(result.errors, isEmpty);
  });

  test('re-running scans again and keeps cursors', () async {
    final capability = _FakeCapability(sources: [_source('a')]);
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final cursors = _FakeCursors();
    final service = SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: _FakeStore(),
      cursors: cursors,
      registry: registry,
    );

    await service.syncAll();
    await service.syncAll();

    expect(capability.scans, 2);
    expect(cursors.saved['a']?.byteOffset, 7);
  });

  test('one source failure does not abort the other source', () async {
    final capability = _FakeCapability(
      sources: [_source('bad'), _source('good')],
      failOn: 'bad',
    );
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final store = _FakeStore();
    final service = SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: store,
      cursors: _FakeCursors(),
      registry: registry,
    );

    final result = await service.syncAll();

    expect(result.errors, hasLength(1));
    expect(result.errors.single.sourceId, 'bad');
    expect(store.events, hasLength(1));
  });
}
```

- [x] **Step 2: Write the failing target-provider test**

Create `client/test/services/usage/team_pilot_usage_scan_target_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/usage/team_pilot_usage_scan_target_provider.dart';

import '../../support/in_memory_filesystem.dart';

InMemoryFilesystem _fs() =>
    InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));

void main() {
  test('simple session becomes one target', () async {
    final storage = fakeHomeStorage(filesystem: _fs());
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/home/me/proj')],
      cli: CliTool.claude,
      createdAt: 1,
    );
    final provider = TeamPilotUsageScanTargetProvider(
      storage: storage,
      loadSessions: () async => [session],
      loadTeams: () async => const [],
    );

    final targets = await provider.targets();

    expect(targets, hasLength(1));
    expect(targets.single.cli, CliTool.claude);
    expect(targets.single.sessionId, 's1');
    expect(targets.single.memberId, '');
    expect(targets.single.taskId, 's1');
    expect(targets.single.transcriptRoots, isNotEmpty);
  });

  test('mixed team expands bindings with member CLI and task id', () async {
    final storage = fakeHomeStorage(filesystem: _fs());
    const team = TeamProfile(
      id: 'team1',
      name: 'Team 1',
      members: [
        TeamMemberConfig(id: 'dev', name: 'Dev', cli: CliTool.codex),
      ],
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team1',
      cli: CliTool.claude,
      folders: const [WorkspaceFolder(path: '/home/me/proj')],
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'dev',
          taskId: 'task-dev',
          cli: CliTool.codex,
        ),
      ],
      createdAt: 1,
    );
    final provider = TeamPilotUsageScanTargetProvider(
      storage: storage,
      loadSessions: () async => [session],
      loadTeams: () async => [team],
    );

    final targets = await provider.targets();

    expect(targets, hasLength(1));
    expect(targets.single.cli, CliTool.codex);
    expect(targets.single.memberId, 'dev');
    expect(targets.single.teamId, 'team1');
    expect(targets.single.taskId, 'task-dev');
  });

  test('native team without bindings uses session cli', () async {
    final storage = fakeHomeStorage(filesystem: _fs());
    const team = TeamProfile(id: 'team1', name: 'Team 1');
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team1',
      cli: CliTool.claude,
      folders: const [WorkspaceFolder(path: '/home/me/proj')],
      createdAt: 1,
    );
    final provider = TeamPilotUsageScanTargetProvider(
      storage: storage,
      loadSessions: () async => [session],
      loadTeams: () async => [team],
    );

    final targets = await provider.targets();

    expect(targets, hasLength(1));
    expect(targets.single.cli, CliTool.claude);
    expect(targets.single.memberId, '');
  });
}
```

- [x] **Step 3: Run both and confirm they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/usage/session_usage_sync_service_test.dart
dart run tool/run_tests.dart test/services/usage/team_pilot_usage_scan_target_provider_test.dart
```

Expected: compile failures, the three implementation files are missing.

- [x] **Step 4: Implement the target port**

Create `client/lib/services/usage/usage_scan_target_provider.dart`:

```dart
import '../cli/registry/capabilities/session_usage_capability.dart';

/// Narrow seam so the sync service can be tested without repositories.
abstract interface class UsageScanTargetProvider {
  Future<List<UsageScanContext>> targets();
}
```

- [x] **Step 5: Implement the production target provider**

Create `client/lib/services/usage/team_pilot_usage_scan_target_provider.dart`:

```dart
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../chat/conversation/history/session_history_context_builder.dart';
import '../cli/registry/capabilities/session_usage_capability.dart';
import '../storage/home_storage.dart';
import 'usage_scan_target_provider.dart';

/// Turns TeamPilot sessions and seat bindings into scan contexts.
///
/// Session enumeration is injected as functions so this class does not depend
/// on a repository lifecycle. Production wiring lives in
/// `app/session_usage_services.dart`.
class TeamPilotUsageScanTargetProvider implements UsageScanTargetProvider {
  TeamPilotUsageScanTargetProvider({
    required HomeStorage storage,
    required Future<List<AppSession>> Function() loadSessions,
    required Future<List<TeamProfile>> Function() loadTeams,
    SessionHistoryContextBuilder builder = const SessionHistoryContextBuilder(),
  }) : _storage = storage,
       _loadSessions = loadSessions,
       _loadTeams = loadTeams,
       _builder = builder;

  final HomeStorage _storage;
  final Future<List<AppSession>> Function() _loadSessions;
  final Future<List<TeamProfile>> Function() _loadTeams;
  final SessionHistoryContextBuilder _builder;

  @override
  Future<List<UsageScanContext>> targets() async {
    final sessions = await _loadSessions();
    final teams = await _loadTeams();
    final teamsById = {for (final team in teams) team.id: team};
    final out = <UsageScanContext>[];
    for (final session in sessions) {
      try {
        out.addAll(_targetsFor(session, teamsById[session.sessionTeam]));
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[usage] session target enumeration failed '
          'session=${session.sessionId}: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return out;
  }

  List<UsageScanContext> _targetsFor(AppSession session, TeamProfile? team) {
    if (session.isSimple || session.members.isEmpty) {
      final cli = session.cli ?? team?.cli ?? CliTool.claude;
      final context = _build(session: session, cli: cli, memberId: '');
      return context == null ? const [] : [context];
    }

    final roster = team == null
        ? const <TeamMemberConfig>[]
        : sessionRosterMembers(session, team);
    final rosterById = {for (final member in roster) member.id: member};
    final out = <UsageScanContext>[];
    for (final binding in session.members) {
      final memberId = binding.rosterMemberId.trim();
      if (memberId.isEmpty) continue;
      final cli = binding.cli ?? rosterById[memberId]?.cli ?? session.cli;
      if (cli == null) continue;
      final context = _build(
        session: session,
        cli: cli,
        memberId: memberId,
      );
      if (context != null) out.add(context);
    }
    return out;
  }

  UsageScanContext? _build({
    required AppSession session,
    required CliTool cli,
    required String memberId,
  }) {
    try {
      final work = session.workDirsForMember(
        memberId.isEmpty ? null : memberId,
        folders: session.folders,
        usesPosixPaths: _storage.usesPosixPaths,
      );
      final history = _builder.build(
        fs: _storage.fs,
        layout: _storage.context.layout,
        appDataRoot: _storage.appDataRoot,
        session: session,
        memberId: memberId,
        cli: cli,
        workingDirectory: work.workingDirectory,
        teamId: session.sessionTeam,
      );
      return UsageScanContext(
        fs: history.fs,
        cli: cli,
        env: history.env,
        transcriptRoots: history.transcriptRoots,
        taskId: history.taskId,
        nativeSessionId: history.persistedNativeId ?? '',
        sessionId: history.sessionId ?? session.sessionId,
        memberId: history.memberId ?? '',
        teamId: history.teamId ?? '',
        workingDirectory: work.workingDirectory,
        appDataRoot: _storage.appDataRoot,
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[usage] target build failed session=${session.sessionId} '
        'member=$memberId cli=${cli.value}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
```

- [x] **Step 6: Implement the sync service**

Create `client/lib/services/usage/session_usage_sync_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../cli/registry/capabilities/session_usage_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'usage_cursor_store.dart';
import 'usage_scan_target_provider.dart';
import 'usage_store.dart';

@immutable
class UsageSyncError {
  const UsageSyncError({required this.sourceId, required this.message});

  final String sourceId;
  final String message;
}

@immutable
class UsageSyncResult {
  const UsageSyncResult({
    this.targetsScanned = 0,
    this.sourcesScanned = 0,
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = const [],
  });

  final int targetsScanned;
  final int sourcesScanned;
  final int inserted;
  final int updated;
  final int skipped;
  final List<UsageSyncError> errors;
}

/// One-shot scanner. No timer and no cubit in this slice.
class SessionUsageSyncService {
  SessionUsageSyncService({
    required UsageScanTargetProvider targets,
    required UsageStore store,
    required UsageCursorStore cursors,
    required CliToolRegistry registry,
  }) : _targets = targets,
       _store = store,
       _cursors = cursors,
       _registry = registry;

  final UsageScanTargetProvider _targets;
  final UsageStore _store;
  final UsageCursorStore _cursors;
  final CliToolRegistry _registry;

  /// Process-wide: a plane swap can briefly keep an old service alive.
  static final Lock _syncLock = Lock();

  Future<UsageSyncResult> syncAll() => _syncLock.synchronized(_syncAll);

  Future<UsageSyncResult> _syncAll() async {
    late final List<UsageScanContext> targets;
    try {
      targets = await _targets.targets();
    } on Object catch (error) {
      return UsageSyncResult(
        errors: [
          UsageSyncError(sourceId: '*', message: '$error'),
        ],
      );
    }

    final errors = <UsageSyncError>[];
    final seenSources = <String>{};
    var sourcesScanned = 0;
    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    for (final ctx in targets) {
      final capability = _registry.capability<SessionUsageCapability>(ctx.cli);
      if (capability == null) continue;

      late final List<SessionUsageSource> sources;
      try {
        sources = await capability.discoverUsageSources(ctx);
      } on Object catch (error) {
        errors.add(
          UsageSyncError(
            sourceId: '${ctx.sessionId}/${ctx.memberId}',
            message: '$error',
          ),
        );
        continue;
      }

      for (final source in sources) {
        if (!seenSources.add(source.id)) continue;
        sourcesScanned++;
        try {
          final cursor = await _cursors.read(source.id);
          final scan = await capability.scanUsageSource(
            ctx: ctx,
            source: source,
            cursor: cursor,
          );
          final appended = await _store.upsert(scan.events);
          await _cursors.save(source.id, scan.nextCursor);
          inserted += appended.inserted;
          updated += appended.updated;
          skipped += appended.skipped;
        } on Object catch (error) {
          errors.add(
            UsageSyncError(sourceId: source.id, message: '$error'),
          );
        }
      }
    }

    return UsageSyncResult(
      targetsScanned: targets.length,
      sourcesScanned: sourcesScanned,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }
}
```

- [x] **Step 7: Run the tests and analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/usage/session_usage_sync_service_test.dart test/services/usage/team_pilot_usage_scan_target_provider_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 6 tests pass (3 sync + 3 target).

- [x] **Step 8: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/usage/usage_scan_target_provider.dart \
  client/lib/services/usage/team_pilot_usage_scan_target_provider.dart \
  client/lib/services/usage/session_usage_sync_service.dart \
  client/test/services/usage/session_usage_sync_service_test.dart \
  client/test/services/usage/team_pilot_usage_scan_target_provider_test.dart
git commit -m "feat(usage): add sync service and target enumeration" -- \
  client/lib/services/usage/usage_scan_target_provider.dart \
  client/lib/services/usage/team_pilot_usage_scan_target_provider.dart \
  client/lib/services/usage/session_usage_sync_service.dart \
  client/test/services/usage/session_usage_sync_service_test.dart \
  client/test/services/usage/team_pilot_usage_scan_target_provider_test.dart
```

---

## Task 5: Claude Code extraction

**Files:**
- Create: `client/lib/services/cli/claude/capabilities/usage/session_usage.dart`
- Create: `client/test/services/cli/registry/capabilities/usage/claude_session_usage_test.dart`

- [x] **Step 1: Write the failing Claude test**

Create the test file:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _root = '/tp/cli-defaults/claude';

UsageScanContext _ctx({String nativeId = 'native-1'}) => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.claude,
  env: const {},
  transcriptRoots: const [_root],
  taskId: 'task-1',
  nativeSessionId: nativeId,
  sessionId: 's1',
  memberId: 'dev',
  teamId: 'team1',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

String _line({
  required String id,
  int input = 10,
  int output = 2,
  int cacheRead = 0,
  int cacheCreate = 0,
  String? stopReason = 'end_turn',
  int cache1h = 0,
}) {
  return jsonEncode({
    'type': 'assistant',
    'timestamp': '2026-10-26T10:00:00.000Z',
    'message': {
      'id': id,
      'model': 'claude-sonnet-4',
      'stop_reason': stopReason,
      'usage': {
        'input_tokens': input,
        'output_tokens': output,
        'cache_read_input_tokens': cacheRead,
        'cache_creation_input_tokens': cacheCreate,
        if (cache1h > 0)
          'cache_creation': {'ephemeral_1h_input_tokens': cache1h},
      },
    },
  });
}

void main() {
  test('discovers the seat transcript and its subagent children', () async {
    final ctx = _ctx();
    await ctx.fs.writeString(
      p.join(_root, 'projects', '-home-me-proj', 'native-1.jsonl'),
      '',
    );
    await ctx.fs.writeString(
      p.join(
        _root,
        'projects',
        '-home-me-proj',
        'native-1',
        'subagents',
        'agent-a.jsonl',
      ),
      '',
    );
    await ctx.fs.writeString(
      p.join(_root, 'projects', '-home-me-proj', 'other.jsonl'),
      '',
    );

    final sources = await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(2));
    expect(sources.every((s) => s.id.startsWith('claude-jsonl:')), isTrue);
  });

  test('parses usage, finality, cache, and 1h cache', () async {
    final ctx = _ctx();
    final path = p.join(
      _root,
      'projects',
      '-home-me-proj',
      'native-1.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_line(id: 'm1', input: 100, output: 20, cacheRead: 30, cacheCreate: 10, cache1h: 5)}\n',
    );
    final source = (await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;

    final scan = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    final event = scan.events.single;
    expect(event.requestId, 'claude:m1');
    expect(event.cli, CliTool.claude);
    expect(event.model, 'claude-sonnet-4');
    expect(event.inputTokens, 100);
    expect(event.outputTokens, 20);
    expect(event.cacheReadTokens, 30);
    expect(event.cacheCreationTokens, 10);
    expect(event.cacheCreation1hTokens, 5);
    expect(event.inputSemantics, UsageInputSemantics.fresh);
    expect(event.isFinal, isTrue);
    expect(event.sessionId, 's1');
    expect(event.memberId, 'dev');
    expect(event.teamId, 'team1');
  });

  test('non-final message stays importable and is replaced later', () async {
    final ctx = _ctx();
    final path = p.join(
      _root,
      'projects',
      '-home-me-proj',
      'native-1.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_line(id: 'm1', output: 1, stopReason: null)}\n',
    );
    final source = (await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final first = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(first.events.single.isFinal, isFalse);
    expect(first.events.single.outputTokens, 1);

    await ctx.fs.appendString(
      path,
      '${_line(id: 'm1', output: 9, stopReason: 'end_turn')}\n',
    );
    final second = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events.single.isFinal, isTrue);
    expect(second.events.single.outputTokens, 9);
  });

  test('skips zero-usage and malformed lines', () async {
    final ctx = _ctx();
    final path = p.join(
      _root,
      'projects',
      '-home-me-proj',
      'native-1.jsonl',
    );
    await ctx.fs.writeString(
      path,
      'not-json\n${_line(id: 'm1', input: 0, output: 0)}\n${_line(id: 'm2')}\n',
    );
    final source = (await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;

    final scan = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(scan.events, hasLength(1));
    expect(scan.events.single.requestId, 'claude:m2');
    expect(scan.skippedLines, 1);
  });
}
```

- [x] **Step 2: Run it and confirm it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/cli/registry/capabilities/usage/claude_session_usage_test.dart
```

Expected: compile failure, implementation missing.

- [x] **Step 3: Implement the Claude capability**

Create `client/lib/services/cli/claude/capabilities/usage/session_usage.dart`:

```dart
import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';

final class ClaudeSessionUsageCapability implements SessionUsageCapability {
  const ClaudeSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final ids = {
      for (final id in [ctx.nativeSessionId, ctx.taskId])
        if (id.trim().isNotEmpty) id.trim(),
    };
    if (ids.isEmpty) return const [];

    final path = ctx.fs.pathContext;
    final seen = <String>{};
    final out = <SessionUsageSource>[];
    for (final root in ctx.transcriptRoots) {
      final projects = path.join(root, 'projects');
      if (!(await ctx.fs.stat(projects)).isDirectory) continue;
      for (final entry in await ctx.fs.listDirRecursive(projects)) {
        if (entry.isDirectory) continue;
        final segments = path.split(entry.name);
        final basename = path.basename(entry.name);
        if (!basename.endsWith('.jsonl')) continue;
        final owned = ids.any(
          (id) =>
              basename == '$id.jsonl' ||
              (segments.length > 1 && segments.skip(1).contains(id)),
        );
        if (!owned) continue;
        final full = path.join(projects, entry.name);
        if (!seen.add(full)) continue;
        out.add(
          SessionUsageSource(
            id: 'claude-jsonl:$full',
            path: full,
            kind: UsageSourceKind.jsonl,
            sessionId: ctx.sessionId,
            memberId: ctx.memberId,
            teamId: ctx.teamId,
          ),
        );
      }
    }
    return out;
  }

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    final window = await readJsonlUsageWindow(
      fs: ctx.fs,
      path: source.path,
      cursor: cursor,
    );
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    for (var i = 0; i < window.lines.length; i++) {
      final line = window.lines[i].trim();
      if (line.isEmpty) continue;
      Map<String, Object?>? obj;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) obj = Map<String, Object?>.from(decoded);
      } on Object {
        skipped++;
        continue;
      }
      if (obj == null) {
        skipped++;
        continue;
      }
      if (obj['type'] != 'assistant') continue;
      final messageRaw = obj['message'];
      if (messageRaw is! Map) continue;
      final message = Map<String, Object?>.from(messageRaw);
      final usageRaw = message['usage'];
      if (usageRaw is! Map) continue;
      final usage = Map<String, Object?>.from(usageRaw);
      final input = _int(usage['input_tokens']);
      final output = _int(usage['output_tokens']);
      final cacheRead = _int(usage['cache_read_input_tokens']);
      final cacheCreate = _int(usage['cache_creation_input_tokens']);
      final cacheMap = usage['cache_creation'];
      final cache1h = cacheMap is Map
          ? _int(cacheMap['ephemeral_1h_input_tokens'])
          : 0;
      if (input == 0 && output == 0 && cacheRead == 0 && cacheCreate == 0) {
        continue;
      }
      final messageId = '${message['id'] ?? ''}'.trim();
      if (messageId.isEmpty) continue;
      final stopReason = message['stop_reason'];
      events.add(
        SessionUsageEvent(
          requestId: 'claude:$messageId',
          cli: CliTool.claude,
          model: '${message['model'] ?? ''}',
          inputTokens: input,
          outputTokens: output,
          cacheReadTokens: cacheRead,
          cacheCreationTokens: cacheCreate,
          cacheCreation1hTokens: cache1h.clamp(0, cacheCreate),
          inputSemantics: UsageInputSemantics.fresh,
          timestampMs: _timestampMs(obj['timestamp']),
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
          isFinal: stopReason != null && '$stopReason'.trim().isNotEmpty,
        ),
      );
    }
    return UsageScanResult(
      events: events,
      nextCursor: window.nextCursor,
      partialTail: window.partialTail,
      skippedLines: skipped,
    );
  }
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

int _timestampMs(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) {
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}
```

- [x] **Step 4: Run the test and analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/cli/registry/capabilities/usage/claude_session_usage_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 4 tests pass.

- [x] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/claude/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/claude_session_usage_test.dart
git commit -m "feat(usage): add claude transcript extraction" -- \
  client/lib/services/cli/claude/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/claude_session_usage_test.dart
```

---

## Task 6: Codex extraction

**Files:**
- Create: `client/lib/services/cli/codex/capabilities/usage/session_usage.dart`
- Create: `client/test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart`

- [x] **Step 1: Write the failing Codex test**

Create the test file:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _home = '/tp/runtime/codex';
const _thread = '11111111-1111-1111-1111-111111111111';

UsageScanContext _ctx() => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.codex,
  env: const {'CODEX_HOME': _home},
  transcriptRoots: const [],
  taskId: 'task-1',
  nativeSessionId: _thread,
  sessionId: 's1',
  memberId: '',
  teamId: '',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

String _tokenCount({
  Map<String, Object?>? last,
  Map<String, Object?>? total,
}) {
  return jsonEncode({
    'type': 'event_msg',
    'timestamp': '2026-10-26T10:00:00.000Z',
    'payload': {
      'type': 'token_count',
      'info': {
        if (last != null) 'last_token_usage': last,
        if (total != null) 'total_token_usage': total,
      },
    },
  });
}

Map<String, Object?> _usage({
  required int input,
  required int cached,
  required int output,
}) => {
  'input_tokens': input,
  'cached_input_tokens': cached,
  'output_tokens': output,
};

void main() {
  test('discovers rollouts under CODEX_HOME', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(path, '');

    final sources = await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(1));
    expect(sources.single.kind, UsageSourceKind.jsonl);
  });

  test('uses last_token_usage and keeps the cumulative baseline', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_tokenCount(last: _usage(input: 100, cached: 40, output: 10), total: _usage(input: 100, cached: 40, output: 10))}\n',
    );
    final source = (await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final first = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    final event = first.events.single;
    expect(event.requestId, startsWith('codex:$_thread:'));
    expect(event.inputTokens, 100);
    expect(event.cacheReadTokens, 40);
    expect(event.outputTokens, 10);
    expect(event.inputSemantics, UsageInputSemantics.total);
    expect(event.freshInputTokens, 60);
    expect(first.nextCursor.storeToken, '100,10,40,0');

    await ctx.fs.appendString(
      path,
      '${_tokenCount(last: _usage(input: 20, cached: 5, output: 3), total: _usage(input: 120, cached: 45, output: 13))}\n',
    );
    final second = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events.single.inputTokens, 20);
    expect(second.events.single.cacheReadTokens, 5);
    expect(second.events.single.outputTokens, 3);
    expect(second.nextCursor.storeToken, '120,13,45,0');
  });

  test('derives a delta when only total_token_usage is present', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_tokenCount(total: _usage(input: 100, cached: 40, output: 10))}\n',
    );
    final source = (await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final first = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    await ctx.fs.appendString(
      path,
      '${_tokenCount(total: _usage(input: 150, cached: 50, output: 18))}\n',
    );
    final second = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events.single.inputTokens, 50);
    expect(second.events.single.cacheReadTokens, 10);
    expect(second.events.single.outputTokens, 8);
  });

  test('clamps cache counters to input', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_tokenCount(last: {'input_tokens': 10, 'cached_input_tokens': 99, 'cache_write_input_tokens': 99, 'output_tokens': 1})}\n',
    );
    final source = (await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final scan = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(scan.events.single.cacheReadTokens, 10);
    expect(scan.events.single.cacheCreationTokens, 0);
  });
}
```

- [x] **Step 2: Run it and confirm it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
```

- [x] **Step 3: Implement the Codex capability**

Create `client/lib/services/cli/codex/capabilities/usage/session_usage.dart`:

```dart
import 'dart:convert';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../../../../usage/jsonl_usage_cursor_reader.dart';
import '../history/root_rollout.dart';

const String _pinToken = 'pin';

final class CodexSessionUsageCapability implements SessionUsageCapability {
  const CodexSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final home = ctx.env['CODEX_HOME']?.trim() ?? '';
    if (home.isEmpty) return const [];
    final path = ctx.fs.pathContext;
    final sessions = path.join(home, 'sessions');
    if (!(await ctx.fs.stat(sessions)).isDirectory) return const [];

    final out = <SessionUsageSource>[];
    for (final entry in await ctx.fs.listDirRecursive(sessions)) {
      if (entry.isDirectory) continue;
      final basename = path.basename(entry.name);
      if (!basename.startsWith('rollout-') || !basename.endsWith('.jsonl')) {
        continue;
      }
      final full = path.join(sessions, entry.name);
      out.add(
        SessionUsageSource(
          id: 'codex-jsonl:$full',
          path: full,
          kind: UsageSourceKind.jsonl,
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
        ),
      );
    }
    return out;
  }

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    final window = await readJsonlUsageWindow(
      fs: ctx.fs,
      path: source.path,
      cursor: cursor,
    );
    final path = ctx.fs.pathContext;
    final match = codexRolloutId.firstMatch(path.basename(source.path));
    final threadId =
        match?.group(1) ?? path.basenameWithoutExtension(source.path);

    final resetAfterPin = cursor?.storeToken == _pinToken;
    var baseline = resetAfterPin ? null : _Counters.decode(cursor?.storeToken);
    var nextBaseline = baseline;
    var skipFirstTotal = resetAfterPin;
    final events = <SessionUsageEvent>[];
    var skipped = 0;

    for (var i = 0; i < window.lines.length; i++) {
      final line = window.lines[i].trim();
      if (line.isEmpty) continue;
      Map<String, Object?>? obj;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) obj = Map<String, Object?>.from(decoded);
      } on Object {
        skipped++;
        continue;
      }
      if (obj == null) {
        skipped++;
        continue;
      }
      if (obj['type'] != 'event_msg') continue;
      final payloadRaw = obj['payload'];
      if (payloadRaw is! Map) continue;
      final payload = Map<String, Object?>.from(payloadRaw);
      if (payload['type'] != 'token_count') continue;
      final infoRaw = payload['info'];
      if (infoRaw is! Map) continue;
      final info = Map<String, Object?>.from(infoRaw);

      final last = _Counters.fromUsage(info['last_token_usage']);
      final total = _Counters.fromUsage(info['total_token_usage']);
      _Counters? counters = null;
      if (last != null && last.anyPositive) {
        counters = last.clamped();
        skipFirstTotal = false;
      } else if (total != null) {
        if (skipFirstTotal) {
          skipFirstTotal = false;
        } else {
          counters = total.deltaFrom(baseline);
        }
      }
      if (total != null) {
        baseline = total;
        nextBaseline = total;
      }
      if (counters == null || !counters.anyPositive) continue;

      events.add(
        SessionUsageEvent(
          requestId: 'codex:$threadId:${window.lineOffsets[i]}',
          cli: CliTool.codex,
          model: '',
          inputTokens: counters.input,
          outputTokens: counters.output,
          cacheReadTokens: counters.cacheRead,
          cacheCreationTokens: counters.cacheWrite,
          inputSemantics: UsageInputSemantics.total,
          timestampMs: _timestampMs(obj['timestamp']),
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
          isFinal: true,
        ),
      );
    }

    if (window.pinnedToEof) {
      nextBaseline = null;
    }

    return UsageScanResult(
      events: events,
      nextCursor: UsageCursor(
        byteOffset: window.nextCursor.byteOffset,
        mtimeMs: window.nextCursor.mtimeMs,
        size: window.nextCursor.size,
        tailFingerprint: window.nextCursor.tailFingerprint,
        lineOffset: window.nextCursor.lineOffset,
        storeToken: window.pinnedToEof ? _pinToken : nextBaseline?.encode(),
      ),
      partialTail: window.partialTail,
      skippedLines: skipped,
    );
  }
}

final class _Counters {
  const _Counters({
    required this.input,
    required this.output,
    required this.cacheRead,
    required this.cacheWrite,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  bool get anyPositive =>
      input > 0 || output > 0 || cacheRead > 0 || cacheWrite > 0;

  _Counters clamped() {
    final read = cacheRead.clamp(0, input);
    final write = cacheWrite.clamp(0, input - read);
    return _Counters(
      input: input,
      output: output,
      cacheRead: read,
      cacheWrite: write,
    );
  }

  _Counters? deltaFrom(_Counters? baseline) {
    if (baseline == null) return clamped();
    final next = _Counters(
      input: (input - baseline.input).clamp(0, input),
      output: (output - baseline.output).clamp(0, output),
      cacheRead: (cacheRead - baseline.cacheRead).clamp(0, cacheRead),
      cacheWrite: (cacheWrite - baseline.cacheWrite).clamp(0, cacheWrite),
    );
    return next.anyPositive ? next.clamped() : null;
  }

  String encode() => '$input,$output,$cacheRead,$cacheWrite';

  static _Counters? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(',');
    if (parts.length != 4) return null;
    final values = [for (final part in parts) int.tryParse(part)];
    if (values.any((value) => value == null)) return null;
    return _Counters(
      input: values[0]!,
      output: values[1]!,
      cacheRead: values[2]!,
      cacheWrite: values[3]!,
    );
  }

  static _Counters? fromUsage(Object? raw) {
    if (raw is! Map) return null;
    final input = _int(raw['input_tokens']);
    final cachedRaw = raw['cached_input_tokens'];
    final cacheRead = cachedRaw != null
        ? _int(cachedRaw)
        : _int(raw['cache_read_input_tokens']);
    return _Counters(
      input: input,
      output: _int(raw['output_tokens']),
      cacheRead: cacheRead,
      cacheWrite: _int(raw['cache_write_input_tokens']),
    );
  }
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

int _timestampMs(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) {
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}
```

- [x] **Step 4: Run the test and analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 4 tests pass.

- [x] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/codex/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
git commit -m "feat(usage): add codex rollout extraction" -- \
  client/lib/services/cli/codex/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
```

---

## Task 7: OpenCode extraction

**Files:**
- Create: `client/lib/services/cli/opencode/capabilities/usage/session_usage.dart`
- Create: `client/test/services/cli/registry/capabilities/usage/opencode_session_usage_test.dart`

- [x] **Step 1: Write the failing OpenCode test**

Create the test file:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/cli/opencode/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../../../../support/opencode_v2_sqlite.dart';

void main() {
  late Directory base;
  late String dbPath;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_usage_');
    dbPath = p.join(base.path, 'opencode.db');
  });

  tearDown(() async {
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
    if (await base.exists()) await base.delete(recursive: true);
  });

  UsageScanContext ctx() => UsageScanContext(
    fs: fs,
    cli: CliTool.opencode,
    env: {'OPENCODE_DB': dbPath},
    transcriptRoots: const [],
    taskId: 'task-1',
    nativeSessionId: 'ses_1',
    sessionId: 's1',
    memberId: 'dev',
    teamId: 'team1',
    workingDirectory: '/home/me/proj',
    appDataRoot: '/tp',
  );

  void writeAssistant({
    required String id,
    required int seq,
    required Map<String, Object?> tokens,
    String model = 'claude-sonnet-4',
    int timeCreated = 1000,
    double? cost,
  }) {
    final db = sqlite3.open(dbPath);
    try {
      final hasSchema = db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' "
        "AND name = 'session_message' LIMIT 1",
      ).isNotEmpty;
      if (!hasSchema) createOpencodeV2Schema(db);
      db.execute(
        'INSERT OR REPLACE INTO session_message '
        '(id, session_id, type, seq, time_created, time_updated, data) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          'ses_1',
          'assistant',
          seq,
          timeCreated,
          timeCreated,
          jsonEncode({
            'role': 'assistant',
            'model': {'id': model},
            'tokens': tokens,
            if (cost != null) 'cost': cost,
            'time': {'created': timeCreated},
          }),
        ],
      );
    } finally {
      db.close();
    }
  }

  test('discovers the seat database', () async {
    writeAssistant(
      id: 'msg_1',
      seq: 1,
      tokens: {'input': 10, 'output': 2},
    );

    final sources = await const OpencodeSessionUsageCapability()
        .discoverUsageSources(ctx());

    expect(sources, hasLength(1));
    expect(sources.single.kind, UsageSourceKind.sqlite);
    expect(sources.single.path, dbPath);
  });

  test('parses fresh input, reasoning, cache, and cost', () async {
    writeAssistant(
      id: 'msg_1',
      seq: 1,
      tokens: {
        'input': 100,
        'output': 20,
        'reasoning': 5,
        'cache': {'read': 30, 'write': 10},
      },
      cost: 0.012345,
    );
    final source = (await const OpencodeSessionUsageCapability()
        .discoverUsageSources(ctx()))
        .single;

    final scan = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: null,
    );

    final event = scan.events.single;
    expect(event.requestId, 'opencode:msg_1');
    expect(event.inputTokens, 100);
    expect(event.outputTokens, 25);
    expect(event.cacheReadTokens, 30);
    expect(event.cacheCreationTokens, 10);
    expect(event.inputSemantics, UsageInputSemantics.fresh);
    expect(event.costMicroUsd, 12345);
    expect(event.model, 'claude-sonnet-4');
  });

  test('skips user and zero-token messages', () async {
    final db = sqlite3.open(dbPath);
    try {
      createOpencodeV2Schema(db);
      insertOpencodeV2User(
        db,
        id: 'msg_user',
        sessionId: 'ses_1',
        seq: 1,
        text: 'hi',
      );
      db.execute(
        'INSERT INTO session_message '
        '(id, session_id, type, seq, time_created, time_updated, data) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'msg_zero',
          'ses_1',
          'assistant',
          2,
          1000,
          1000,
          jsonEncode({
            'role': 'assistant',
            'tokens': {'input': 0, 'output': 0},
          }),
        ],
      );
    } finally {
      db.close();
    }
    final source = (await const OpencodeSessionUsageCapability()
        .discoverUsageSources(ctx()))
        .single;

    final scan = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: null,
    );

    expect(scan.events, isEmpty);
  });

  test('returns nothing when the snapshot token is unchanged', () async {
    writeAssistant(
      id: 'msg_1',
      seq: 1,
      tokens: {'input': 10, 'output': 2},
    );
    final source = (await const OpencodeSessionUsageCapability()
        .discoverUsageSources(ctx()))
        .single;
    final first = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: null,
    );
    final second = await const OpencodeSessionUsageCapability().scanUsageSource(
      ctx: ctx(),
      source: source,
      cursor: first.nextCursor,
    );

    expect(first.events, hasLength(1));
    expect(second.events, isEmpty);
    expect(second.nextCursor.storeToken, first.nextCursor.storeToken);
  });
}
```

- [x] **Step 2: Run it and confirm it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/cli/registry/capabilities/usage/opencode_session_usage_test.dart
```

- [x] **Step 3: Implement the OpenCode capability**

Create `client/lib/services/cli/opencode/capabilities/usage/session_usage.dart`:

```dart
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../../../../models/session_usage.dart';
import '../../../../../models/team_config.dart';
import '../../../registry/capabilities/session_usage_capability.dart';
import '../native_session_id.dart';
import '../sqlite_worker_pool.dart';

final class OpencodeSessionUsageCapability implements SessionUsageCapability {
  const OpencodeSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    final dbPath = ctx.env['OPENCODE_DB']?.trim() ?? '';
    if (dbPath.isEmpty) return const [];
    if (!(await ctx.fs.stat(dbPath)).isFile) return const [];
    return [
      SessionUsageSource(
        id: 'opencode-sqlite:$dbPath',
        path: dbPath,
        kind: UsageSourceKind.sqlite,
        sessionId: ctx.sessionId,
        memberId: ctx.memberId,
        teamId: ctx.teamId,
      ),
    ];
  }

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    final handle = await resolveOpencodeSqliteReadPath(
      fs: ctx.fs,
      dbPath: source.path,
    );
    if (handle == null) {
      return UsageScanResult(
        events: const [],
        nextCursor: cursor ?? UsageCursor.empty,
      );
    }

    final result = await OpencodeSqliteWorkerPool.instance
        .run<Map<String, Object?>>(
          dbPath: handle.path,
          query: _readUsageRows,
        );
    if (result == null) {
      throw StateError('opencode usage query failed: ${source.path}');
    }
    final token = '${result['token'] ?? ''}';
    if (cursor?.storeToken == token) {
      return UsageScanResult(events: const [], nextCursor: cursor!);
    }

    final rows = (result['rows'] as List?) ?? const [];
    final events = <SessionUsageEvent>[];
    var skipped = 0;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, Object?>.from(raw);
      final dataRaw = row['data'];
      Map<String, Object?>? data;
      try {
        final decoded = jsonDecode('${dataRaw ?? ''}');
        if (decoded is Map) data = Map<String, Object?>.from(decoded);
      } on Object {
        skipped++;
        continue;
      }
      if (data == null) {
        skipped++;
        continue;
      }
      final isAssistant =
          row['type'] == 'assistant' || data['role'] == 'assistant';
      if (!isAssistant) continue;
      final tokensRaw = data['tokens'];
      if (tokensRaw is! Map) continue;
      final tokens = Map<String, Object?>.from(tokensRaw);
      final input = _int(tokens['input']);
      final output = _int(tokens['output']);
      final reasoning = _int(tokens['reasoning']);
      final cacheRaw = tokens['cache'];
      final cache = cacheRaw is Map
          ? Map<String, Object?>.from(cacheRaw)
          : const <String, Object?>{};
      final cacheRead = _int(cache['read']);
      final cacheWrite = _int(cache['write']);
      if (input == 0 && output == 0 && reasoning == 0 && cacheRead == 0 &&
          cacheWrite == 0) {
        continue;
      }
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final cost = data['cost'];
      events.add(
        SessionUsageEvent(
          requestId: 'opencode:$id',
          cli: CliTool.opencode,
          model: _modelFrom(data),
          inputTokens: input,
          outputTokens: output + reasoning,
          cacheReadTokens: cacheRead,
          cacheCreationTokens: cacheWrite,
          inputSemantics: UsageInputSemantics.fresh,
          timestampMs: _timestampMs(data, row),
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          teamId: ctx.teamId,
          isFinal: true,
          costMicroUsd: cost is num ? (cost * 1000000).round() : null,
        ),
      );
    }

    return UsageScanResult(
      events: events,
      nextCursor: UsageCursor(storeToken: token),
      skippedLines: skipped,
    );
  }
}

/// V2 `session_message` first, legacy V1 `message` second.
///
/// Top-level function: runs in the OpenCode SQLite worker isolate.
Map<String, Object?>? _readUsageRows(Database db, Object? args) {
  final v2 = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'session_message' LIMIT 1",
  );
  if (v2.isNotEmpty) {
    final columns = db.select('PRAGMA table_info(session_message)');
    final hasSeq = columns.any((row) => row['name'] == 'seq');
    final hasUpdated = columns.any((row) => row['name'] == 'time_updated');
    final timeColumn = hasUpdated ? 'time_updated' : 'time_created';
    final rows = db.select(
      'SELECT id, type, data, time_created'
      '${hasUpdated ? ', time_updated' : ''}'
      '${hasSeq ? ', seq' : ''} '
      'FROM session_message '
      'ORDER BY ${hasSeq ? 'seq ASC, id ASC' : 'time_created ASC, id ASC'}',
    );
    return {
      'token': _snapshotToken(
        rows,
        timeColumn: timeColumn,
        countColumn: hasSeq ? 'seq' : null,
      ),
      'rows': [
        for (final row in rows)
          {
            'id': row['id'],
            'type': row['type'],
            'data': row['data'],
            'time_created': row['time_created'],
          },
      ],
    };
  }

  final v1 = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
    "AND name = 'message' LIMIT 1",
  );
  if (v1.isEmpty) {
    throw StateError('opencode usage: neither session_message nor message');
  }
  final rows = db.select(
    'SELECT id, data, time_created FROM message '
    'ORDER BY time_created ASC, id ASC',
  );
  return {
    'token': _snapshotToken(rows, timeColumn: 'time_created', countColumn: null),
    'rows': [
      for (final row in rows)
        {
          'id': row['id'],
          'type': null,
          'data': row['data'],
          'time_created': row['time_created'],
        },
    ],
  };
}

String _snapshotToken(
  ResultSet rows, {
  required String timeColumn,
  required String? countColumn,
}) {
  var maxTime = 0;
  var maxSeq = 0;
  for (final row in rows) {
    final time = row[timeColumn];
    if (time is num && time.toInt() > maxTime) maxTime = time.toInt();
    if (countColumn != null) {
      final seq = row[countColumn];
      if (seq is num && seq.toInt() > maxSeq) maxSeq = seq.toInt();
    }
  }
  return 'oc|${rows.length}|$maxTime|$maxSeq';
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

String _modelFrom(Map<String, Object?> data) {
  final direct = data['modelID'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();
  final model = data['model'];
  if (model is String) return model.trim();
  if (model is Map) return '${model['id'] ?? ''}'.trim();
  return '';
}

int _timestampMs(Map<String, Object?> data, Map<String, Object?> row) {
  final time = data['time'];
  if (time is Map) {
    final created = time['created'];
    if (created is num) return created.toInt();
  }
  final created = row['time_created'];
  return created is num ? created.toInt() : 0;
}
```

- [x] **Step 4: Run the test and analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/cli/registry/capabilities/usage/opencode_session_usage_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 4 tests pass. If the worker returns `null` on the first test, check that the query function is top-level and that `sqlite3` is initialized for the test host (existing OpenCode tests already do this).

- [x] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/opencode/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/opencode_session_usage_test.dart
git commit -m "feat(usage): add opencode sqlite extraction" -- \
  client/lib/services/cli/opencode/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/opencode_session_usage_test.dart
```

---

## Task 8: Register capabilities and add composition factory

**Files:**
- Modify: `client/lib/services/cli/claude/claude_tool.dart`
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`
- Create: `client/lib/app/session_usage_services.dart`
- Create: `client/test/app/session_usage_services_test.dart`
- Create: `client/test/services/cli/registry/session_usage_registration_test.dart`

- [x] **Step 1: Write the failing registration test**

Create `client/test/services/cli/registry/session_usage_registration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('claude, codex, and opencode register usage extraction', () {
    final registry = CliToolRegistry.builtIn();

    expect(
      registry.capability<SessionUsageCapability>(CliTool.claude),
      isNotNull,
    );
    expect(
      registry.capability<SessionUsageCapability>(CliTool.codex),
      isNotNull,
    );
    expect(
      registry.capability<SessionUsageCapability>(CliTool.opencode),
      isNotNull,
    );
  });

  test('clis without extraction stay null', () {
    final registry = CliToolRegistry.builtIn();

    expect(
      registry.capability<SessionUsageCapability>(CliTool.cursor),
      isNull,
    );
    expect(
      registry.capability<SessionUsageCapability>(CliTool.gemini),
      isNull,
    );
  });
}
```

- [x] **Step 2: Run it and confirm it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/cli/registry/session_usage_registration_test.dart
```

Expected: `claude` capability is null.

- [x] **Step 3: Register Claude**

In `client/lib/services/cli/claude/claude_tool.dart`:

Add import:

```dart
import 'capabilities/usage/session_usage.dart';
```

Add constructor parameter after `this.aiHistory = const ClaudeAiHistoryCapability(),`:

```dart
    this.sessionUsage = const ClaudeSessionUsageCapability(),
```

Add field after `final ClaudeAiHistoryCapability aiHistory;`:

```dart
  final SessionUsageCapability sessionUsage;
```

Add `SessionUsageCapability` to the imports (the capability port):

```dart
import '../registry/capabilities/session_usage_capability.dart';
```

Add `sessionUsage,` to `capabilities` after `aiHistory,`.

- [x] **Step 4: Register Codex**

In `client/lib/services/cli/codex/codex_tool.dart`:

```dart
import 'capabilities/usage/session_usage.dart';
import '../registry/capabilities/session_usage_capability.dart';
```

Constructor after `this.aiHistory = const CodexAiHistoryCapability(),`:

```dart
    this.sessionUsage = const CodexSessionUsageCapability(),
```

Field after `final CodexAiHistoryCapability aiHistory;`:

```dart
  final SessionUsageCapability sessionUsage;
```

List after `aiHistory,`:

```dart
    sessionUsage,
```

- [x] **Step 5: Register OpenCode**

In `client/lib/services/cli/opencode/opencode_tool.dart`:

```dart
import 'capabilities/usage/session_usage.dart';
import '../registry/capabilities/session_usage_capability.dart';
```

Constructor after `this.aiHistory = const OpencodeAiHistoryCapability(),`:

```dart
    this.sessionUsage = const OpencodeSessionUsageCapability(),
```

Field after `final OpencodeAiHistoryCapability aiHistory;`:

```dart
  final SessionUsageCapability sessionUsage;
```

List after `aiHistory,`:

```dart
    sessionUsage,
```

- [x] **Step 6: Add the composition factory**

Create `client/lib/app/session_usage_services.dart` (app layer: it may import repositories):

```dart
import '../models/app_session.dart';
import '../models/session_usage.dart';
import '../models/team_config.dart';
import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/storage/home_storage.dart';
import '../services/usage/json_usage_cursor_store.dart';
import '../services/usage/json_usage_store.dart';
import '../services/usage/session_usage_sync_service.dart';
import '../services/usage/team_pilot_usage_scan_target_provider.dart';

/// App-level wiring for one home plane.
///
/// Construct once per [HomeStorage] plane (or rebuild after a plane swap). No
/// timer or widget owns this yet; callers invoke [syncAll] explicitly.
final class SessionUsageServices {
  SessionUsageServices._({required this.syncAll, required this.loadEvents});

  final Future<UsageSyncResult> Function() syncAll;
  final Future<List<SessionUsageEvent>> Function() loadEvents;

  factory SessionUsageServices.forStorage({
    required HomeStorage storage,
    CliToolRegistry? registry,
    SessionRepository? sessions,
    LaunchProfileRepository? teams,
    Future<List<AppSession>> Function()? loadSessions,
    Future<List<TeamProfile>> Function()? loadTeams,
  }) {
    // The `??` right-hand sides are lazy: tests can inject loaders and skip
    // constructing repositories entirely.
    final loadSessionsFn =
        loadSessions ??
        (sessions ?? SessionRepository(storage: storage)).loadSessions;
    final loadTeamsFn =
        loadTeams ??
        (teams ?? LaunchProfileRepository(storage: storage)).loadTeamProfiles;
    final store = JsonUsageStore(
      fs: storage.fs,
      filePath: storage.paths.usageEventsFile,
    );
    final sync = SessionUsageSyncService(
      targets: TeamPilotUsageScanTargetProvider(
        storage: storage,
        loadSessions: loadSessionsFn,
        loadTeams: loadTeamsFn,
      ),
      store: store,
      cursors: JsonUsageCursorStore(
        fs: storage.fs,
        filePath: storage.paths.usageCursorsFile,
      ),
      registry: registry ?? CliToolRegistry.builtIn(),
    );
    return SessionUsageServices._(
      syncAll: sync.syncAll,
      loadEvents: store.readLatest,
    );
  }
}
```

- [x] **Step 7: Write the factory smoke test**

Create `client/test/app/session_usage_services_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/app/session_usage_services.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('factory builds against empty storage and syncs nothing', () async {
    final storage = fakeHomeStorage(
      appDataRoot: '/tp-factory-${DateTime.now().microsecondsSinceEpoch}',
      filesystem: InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      ),
    );
    final services = SessionUsageServices.forStorage(
      storage: storage,
      loadSessions: () async => const [],
      loadTeams: () async => const [],
    );

    final result = await services.syncAll();

    expect(result.targetsScanned, 0);
    expect(result.errors, isEmpty);
  });
}
```

- [x] **Step 8: Run the factory test, registration test, usage suite, and analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/app/session_usage_services_test.dart test/services/cli/registry/session_usage_registration_test.dart
dart run tool/run_tests.dart test/models/session_usage_test.dart test/services/usage/ test/services/cli/registry/capabilities/usage/
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: all usage tests pass; analyzer clean.

- [x] **Step 9: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/claude/claude_tool.dart \
  client/lib/services/cli/codex/codex_tool.dart \
  client/lib/services/cli/opencode/opencode_tool.dart \
  client/lib/app/session_usage_services.dart \
  client/test/app/session_usage_services_test.dart \
  client/test/services/cli/registry/session_usage_registration_test.dart
git commit -m "feat(usage): register cli usage capabilities and wiring" -- \
  client/lib/services/cli/claude/claude_tool.dart \
  client/lib/services/cli/codex/codex_tool.dart \
  client/lib/services/cli/opencode/opencode_tool.dart \
  client/lib/app/session_usage_services.dart \
  client/test/app/session_usage_services_test.dart \
  client/test/services/cli/registry/session_usage_registration_test.dart
```

---

## Task 9: Final verification

- [x] **Step 1: Run the complete usage-focused suite**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart \
  test/models/session_usage_test.dart \
  test/services/usage/ \
  test/services/cli/registry/capabilities/usage/ \
  test/services/cli/registry/session_usage_registration_test.dart
```

Expected: every test passes.

- [x] **Step 2: Run the full analyzer**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no issues.

- [x] **Step 3: Run the full suite in the background**

Per `docs/DEVELOPMENT.md`, run the full suite once before claiming done, in the background, and do not start a second concurrent run:

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart
```

If anything fails in an unrelated area, report it as pre-existing and do not touch user changes.

- [x] **Step 4: Update the plan checkboxes and report**

Mark every completed checkbox in this plan. Report:
- files added/changed,
- test counts and commands,
- any remaining risk (OpenCode full-DB re-read, Claude rewrite pinning, Codex baseline decode),
- that UI/scheduling/pricing/proxy remain out of scope.

- [x] **Step 5: Commit the updated plan**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add docs/superpowers/plans/2026-10-26-agent-cli-usage-tracking.md
git commit -m "docs: mark usage foundation plan complete" -- \
  docs/superpowers/plans/2026-10-26-agent-cli-usage-tracking.md
```

---

## Self-review notes

- **Spec coverage:** event model + semantics, capability port, per-seat target enumeration, JSONL store with revisions, cursor atomicity, Claude/Codex/OpenCode extraction, local+SSH via `Filesystem`, tests, and no UI/scheduler/pricing/proxy.
- **Intentional deviations from the first draft:** OpenCode reads the whole per-seat DB (subagent sessions share it); Codex uses the line byte offset for `requestId` and stores the cumulative baseline in `storeToken`. Both are reflected in the amended spec.
- **No placeholders:** every code block is complete; every command has an expected result.
- **Type consistency:** `UsageCursor`, `UsageScanResult`, `SessionUsageSource`, and `SessionUsageEvent` are used with the same field names across all tasks.
- **File size:** the largest new file is the Codex capability (~230 lines); split `_Counters` into its own file only if it grows.

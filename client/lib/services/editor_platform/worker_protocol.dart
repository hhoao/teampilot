/// Wire protocol between the UI-side `DocumentSession` and a pooled tree-sitter
/// worker (an isolate in production, a fake in tests).
///
/// Design constraints (see the editor-platform spec):
///
/// * The worker owns exactly one parse tree per session and applies commands
///   **serially** — no concurrent edit + query on the same tree.
/// * The worker speaks in **UTF-8 byte offsets** (tree-sitter's native unit);
///   the UI maps those back to Dart `String` code units via `Utf8IndexMap`.
/// * Every command carries a monotonically increasing [seq]. Query replies
///   echo the [TsQueryResult.editSeq] they were computed against so the UI can
///   drop stale replies (`editSeq < latestAppliedEditSeq`).
///
/// All message classes hold only sendable field types (`String`, `int`,
/// `Uint8List`, `List`) so they can cross an isolate boundary unchanged.
library;

import 'dart:async';
import 'dart:typed_data';

/// Base class for every UI → worker command.
sealed class TsCommand {
  const TsCommand({required this.sessionId, required this.seq});

  /// Identifies the target session/tree within the worker.
  final String sessionId;

  /// Monotonic command sequence for this session. Also used to tag which edit
  /// a follow-up query is based on.
  final int seq;
}

/// Opens a new document/tree on the worker.
class TsOpen extends TsCommand {
  const TsOpen({
    required super.sessionId,
    required super.seq,
    required this.grammarId,
    required this.highlightsQuery,
    required this.utf8Bytes,
  });

  /// Selects the compiled grammar to load (matches `LanguagePack.grammarId`).
  final String grammarId;

  /// The pack's `highlights.scm` source. Empty string means "no query" (the
  /// worker parses but returns no captures).
  final String highlightsQuery;

  /// Full document contents as UTF-8 bytes.
  final Uint8List utf8Bytes;
}

/// Applies an incremental edit and re-parses.
///
/// Carries both the tree-sitter [TsEdit.startByte]/`oldEndByte`/`newEndByte`
/// span (so the worker can call `ts_tree_edit` for incremental reuse) and the
/// full post-edit [utf8Bytes] (the new source to re-parse against).
class TsEdit extends TsCommand {
  const TsEdit({
    required super.sessionId,
    required super.seq,
    required this.startByte,
    required this.oldEndByte,
    required this.newEndByte,
    required this.utf8Bytes,
  });

  final int startByte;
  final int oldEndByte;
  final int newEndByte;
  final Uint8List utf8Bytes;
}

/// Requests highlight captures for the byte range `[startByte, endByte)`.
class TsQueryRange extends TsCommand {
  const TsQueryRange({
    required super.sessionId,
    required super.seq,
    required this.requestId,
    required this.startByte,
    required this.endByte,
    this.highPriority = false,
  });

  /// Correlates the eventual [TsQueryResult] back to the awaiting caller.
  final int requestId;

  final int startByte;
  final int endByte;

  /// Hint that this range is on the visible/interaction path. The worker may
  /// use it to order work ahead of background full-file fills.
  final bool highPriority;
}

/// Tears down the session's tree/parser/query on the worker.
class TsDispose extends TsCommand {
  const TsDispose({required super.sessionId, required super.seq});
}

/// A single highlight capture in **byte** coordinates, as returned by a query.
class TsByteCapture {
  const TsByteCapture({
    required this.name,
    required this.startByte,
    required this.endByte,
  });

  /// Capture name without the leading `@` (e.g. `string`, `keyword.control`).
  final String name;
  final int startByte;
  final int endByte;
}

/// Worker → UI reply to a [TsQueryRange].
class TsQueryResult {
  const TsQueryResult({
    required this.sessionId,
    required this.requestId,
    required this.editSeq,
    required this.startByte,
    required this.endByte,
    required this.captures,
  });

  final String sessionId;

  /// Echoes [TsQueryRange.requestId].
  final int requestId;

  /// The [seq] of the most recent [TsOpen]/[TsEdit] the worker had applied when
  /// it computed this result. The UI drops the reply when a newer edit has
  /// since been sent.
  final int editSeq;

  /// The byte range this result covers (echoes the request), so the UI knows
  /// which lines to replace even when there are zero captures.
  final int startByte;
  final int endByte;

  final List<TsByteCapture> captures;
}

/// A shared pool of tree-sitter workers. Sessions are pinned to one worker for
/// their lifetime (session affinity); the pool caps the number of underlying
/// isolates.
abstract class TsWorkerPool {
  /// Acquires (or reuses) a serial channel for [sessionId], pinning it to a
  /// worker.
  TsSessionHandle openSession(String sessionId);

  /// Shuts down all workers.
  Future<void> dispose();
}

/// A per-session channel to its pinned worker.
///
/// Commands sent through a single handle are delivered to the worker **in
/// order**; the worker processes them serially. Query replies for this session
/// arrive on [results].
abstract class TsSessionHandle {
  /// Enqueues a command for the worker. Returns once the command has been
  /// handed off (not once the worker has processed it).
  void send(TsCommand command);

  /// Query replies for this session only.
  Stream<TsQueryResult> get results;

  /// Releases this session's slot on its worker. Callers should send a
  /// [TsDispose] first so the worker frees its native tree.
  void close();
}

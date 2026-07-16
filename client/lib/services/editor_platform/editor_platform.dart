import 'dart:typed_data';

import '../../utils/logging/logger.dart';
import 'language_registry.dart';
import 'tree_sitter_worker_pool.dart';
import 'worker_protocol.dart';

/// App-wide entry point for the tree-sitter editor platform.
///
/// Holds the process-shared [LanguageRegistry] and [TsWorkerPool] so that every
/// open [DocumentSession] talks to the same pooled workers (session affinity
/// is enforced inside the pool). Both are created lazily on first access; the
/// worker pool spawns no isolates until a session with a real grammar opens.
///
/// Tests inject their own fake pool into `EditorCubit` instead of touching this
/// singleton, so the native [TreeSitterWorkerPool] is never built on the plain
/// `flutter test` host.
class EditorPlatform {
  EditorPlatform._();

  static LanguageRegistry? _registry;
  static TsWorkerPool? _workerPool;

  /// The shared language registry (built-in packs).
  static LanguageRegistry get registry =>
      _registry ??= LanguageRegistry.builtins();

  /// The shared tree-sitter worker pool. Backed by [TreeSitterWorkerPool] in
  /// the app; overridable via [overridePlatform] for wiring tests.
  static TsWorkerPool get workerPool =>
      _workerPool ??= TreeSitterWorkerPool();

  /// Best-effort prewarm of the given grammars so the first real file open
  /// isn't cold. Each id opens a short-lived worker session (which loads the
  /// native grammar inside the worker isolate) and immediately disposes it.
  ///
  /// Fire-and-forget from app bootstrap: never blocks app start, and any
  /// failure (e.g. native asset missing on a host) is logged and skipped so
  /// the editor simply falls back to plain text for that language.
  ///
  /// [prewarm] entries are [LanguagePack] ids; unknown ids are used verbatim
  /// as grammar ids.
  static Future<void> bootstrap({
    List<String> prewarm = const ['json', 'dart', 'typescript', 'yaml'],
  }) async {
    for (final id in prewarm) {
      try {
        final grammarId = registry.byId(id)?.grammarId ?? id;
        final sessionId = 'prewarm:$id';
        final handle = workerPool.openSession(sessionId)
          ..send(
            TsOpen(
              sessionId: sessionId,
              seq: 0,
              grammarId: grammarId,
              highlightsQuery: '',
              utf8Bytes: Uint8List(0),
            ),
          )
          ..send(TsDispose(sessionId: sessionId, seq: 1));
        handle.close();
      } catch (error, stackTrace) {
        appLogger.w(
          'EditorPlatform.bootstrap: prewarm "$id" failed; '
          'that language will fall back to plain text',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Overrides the shared [registry] / [workerPool]. Intended for tests and
  /// bootstrap; pass `null` to leave the current value untouched.
  static void overridePlatform({
    LanguageRegistry? registry,
    TsWorkerPool? workerPool,
  }) {
    if (registry != null) _registry = registry;
    if (workerPool != null) _workerPool = workerPool;
  }

  /// Disposes and clears the shared worker pool. Safe to call when nothing has
  /// been created yet.
  static Future<void> dispose() async {
    final pool = _workerPool;
    _workerPool = null;
    await pool?.dispose();
  }
}

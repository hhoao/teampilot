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

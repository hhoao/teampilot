import 'package:teampilot_search/teampilot_search.dart';

import '../file_tree/filesystem_search_reader.dart';
import '../io/filesystem.dart';
import '../io/sftp_filesystem.dart';

/// Runs workspace content search, picking a backend per filesystem:
/// local/WSL paths → Rust engine on a worker isolate; SFTP/SSH or
/// [forceFallback] → pure-Dart fallback over [FilesystemSearchReader] (its
/// filesystem handle is connection-bound and cannot cross isolates).
class ContentSearchRunner {
  ContentSearchRunner({
    required Filesystem fs,
    required String root,
    bool forceFallback = false,
  }) : _fs = fs,
       _root = root,
       _forceFallback = forceFallback;

  final Filesystem _fs;
  final String _root;
  final bool _forceFallback;

  /// The worker-backed engine of the last [run]; cancelled via [cancel] so the
  /// native walker stops even while the isolate is mid-chunk.
  IsolatedContentSearch? _engine;

  bool get _useFallback => _forceFallback || _fs is SftpFilesystem;

  /// 'rust' | 'dart-fallback' — surfaced in the panel footer.
  String get backendLabel => _useFallback ? 'dart-fallback' : 'rust';

  /// Streams matches; a new worker isolate is created per call (the Rust
  /// engine owns a single FFI handle slot).
  Stream<TpSearchMatch> run(TpSearchOptions options) {
    if (_useFallback) {
      return fallbackSearch(FilesystemSearchReader(_fs), _root, options);
    }
    final engine = IsolatedContentSearch();
    _engine = engine;
    return engine.run(_root, options);
  }

  /// Cancels the active walk. No-op on the fallback path, where the pure-Dart
  /// stream stops when its subscription is cancelled.
  void cancel() => _engine?.cancel();
}

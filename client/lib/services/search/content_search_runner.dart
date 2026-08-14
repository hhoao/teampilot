import 'package:teampilot_search/teampilot_search.dart';

import '../file_tree/filesystem_search_reader.dart';
import '../io/filesystem.dart';
import '../io/sftp_filesystem.dart';

/// Runs workspace content search, picking the backend per filesystem:
/// local/WSL paths → Rust engine; SFTP/SSH or [forceFallback] → pure-Dart
/// fallback over [FilesystemSearchReader].
class ContentSearchRunner {
  ContentSearchRunner({
    required Filesystem fs,
    required String root,
    bool forceFallback = false,
  })  : _fs = fs,
        _root = root,
        _forceFallback = forceFallback;

  final Filesystem _fs;
  final String _root;
  final bool _forceFallback;

  /// The engine backing the last [run]; cancelled via [cancel] so the Rust
  /// walker stops even while the Dart side is blocked in a synchronous FFI
  /// chunk read.
  TpSearchEngine? _engine;

  bool get _useFallback => _forceFallback || _fs is SftpFilesystem;

  /// 'rust' | 'dart-fallback' — surfaced in the panel footer.
  String get backendLabel => _useFallback ? 'dart-fallback' : 'rust';

  /// Streams matches; a new Rust engine instance is created per call (the
  /// engine owns a single FFI handle slot).
  Stream<TpSearchMatch> run(TpSearchOptions options) {
    if (_useFallback) {
      return fallbackSearch(FilesystemSearchReader(_fs), _root, options);
    }
    _engine = TpSearchEngine();
    return _engine!.search(_root, options);
  }

  /// Cancels the active Rust engine walk. No-op on the fallback path, where
  /// the pure-Dart stream stops when its subscription is cancelled.
  void cancel() => _engine?.cancel();
}

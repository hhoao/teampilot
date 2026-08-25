import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import '../teampilot_search_bindings_generated.dart' as bindings;

/// Matching algorithm used by [TpFileIndex.query].
enum TpFileMatchMode { fuzzy, contains }

/// Configuration for building a [TpFileIndex].
class TpFileIndexOptions {
  const TpFileIndexOptions({
    this.useGitignore = true,
    this.maxEntries = 200000,
  });

  final bool useGitignore;
  final int maxEntries;
}

/// A file returned by [TpFileIndex.query].
class TpFileHit {
  const TpFileHit({
    required this.path,
    required this.relativePath,
    required this.name,
  });

  final String path;
  final String relativePath;
  final String name;
}

const int _kDefaultStringBufferBytes = 64 * 1024;
const int _kErrRootUnreadable = -2;
const int _kErrInternal = -3;

/// Rust-backed, in-memory file and directory index.
class TpFileIndex {
  ffi.Pointer<bindings.TpFileIndexHandle>? _handle;
  bool _isBuilt = false;
  bool _truncated = false;

  bool get isBuilt => _isBuilt;
  bool get truncated => _truncated;

  /// Builds an index rooted at [root].
  Future<void> build(
    String root, [
    TpFileIndexOptions options = const TpFileIndexOptions(),
  ]) async {
    dispose();
    final handle = _newHandle(root, options);
    _handle = handle;

    final status = await Future(() => bindings.tp_file_index_build(handle));
    if (status < 0) {
      dispose();
      if (status == _kErrRootUnreadable) {
        throw StateError('root unreadable: $root');
      }
      if (status == _kErrInternal) {
        throw StateError('file index build failed internally');
      }
      throw StateError('file index build failed with code $status');
    }
    _isBuilt = true;
  }

  /// Returns matching indexed files.
  List<TpFileHit> query(
    String query, {
    TpFileMatchMode mode = TpFileMatchMode.fuzzy,
    int limit = 50,
  }) {
    final handle = _requireBuilt();
    return _withChunk(limit, (chunk, strings, entries) {
      final cQuery = query.toNativeUtf8();
      try {
        final status = bindings.tp_file_index_query(
          handle,
          cQuery.cast<ffi.Char>(),
          mode == TpFileMatchMode.fuzzy ? 0 : 1,
          limit,
          chunk,
        );
        _checkQueryStatus(status);
        _truncated = chunk.ref.truncated != 0;
        return List.generate(chunk.ref.entries_len, (i) {
          final entry = entries[i];
          return TpFileHit(
            path: _readCStringAt(strings, entry.path),
            relativePath: _readCStringAt(strings, entry.relative_path),
            name: _readCStringAt(strings, entry.name),
          );
        });
      } finally {
        malloc.free(cQuery);
      }
    });
  }

  /// Returns matching indexed directory paths relative to the build root.
  List<String> queryDirectories(String query, {int limit = 20}) {
    final handle = _requireBuilt();
    return _withChunk(limit, (chunk, strings, entries) {
      final cQuery = query.toNativeUtf8();
      try {
        final status = bindings.tp_file_index_query_dirs(
          handle,
          cQuery.cast<ffi.Char>(),
          limit,
          chunk,
        );
        _checkQueryStatus(status);
        _truncated = chunk.ref.truncated != 0;
        return List.generate(
          chunk.ref.entries_len,
          (i) => _readCStringAt(strings, entries[i].relative_path),
        );
      } finally {
        malloc.free(cQuery);
      }
    });
  }

  /// Requests cancellation of an in-progress build.
  void cancel() {
    final handle = _handle;
    if (handle != null) {
      bindings.tp_file_index_cancel(handle);
    }
  }

  /// Frees the native index handle.
  void dispose() {
    final handle = _handle;
    if (handle != null) {
      bindings.tp_file_index_free(handle);
      _handle = null;
    }
    _isBuilt = false;
    _truncated = false;
  }

  ffi.Pointer<bindings.TpFileIndexHandle> _newHandle(
    String root,
    TpFileIndexOptions options,
  ) {
    final cRoot = root.toNativeUtf8();
    final config = calloc<bindings.TpFileIndexConfig>()
      ..ref.root = cRoot.cast<ffi.Char>()
      ..ref.use_gitignore = options.useGitignore ? 1 : 0
      ..ref.max_entries = options.maxEntries
      ..ref.max_chunk_matches = 0
      ..ref.max_chunk_bytes = 0;
    final out = calloc<ffi.Pointer<bindings.TpFileIndexHandle>>();
    try {
      final status = bindings.tp_file_index_new(config, out);
      if (status == _kErrRootUnreadable) {
        throw StateError('root unreadable: $root');
      }
      if (status == _kErrInternal) {
        throw StateError('file index initialization failed internally');
      }
      if (status < 0) {
        throw StateError('file index initialization failed with code $status');
      }
      return out.value;
    } finally {
      malloc.free(cRoot);
      calloc.free(config);
      calloc.free(out);
    }
  }

  ffi.Pointer<bindings.TpFileIndexHandle> _requireBuilt() {
    final handle = _handle;
    if (handle == null || !_isBuilt) {
      throw StateError('file index has not been built');
    }
    return handle;
  }

  T _withChunk<T>(
    int limit,
    T Function(
      ffi.Pointer<bindings.TpFileIndexChunk> chunk,
      ffi.Pointer<ffi.Uint8> strings,
      ffi.Pointer<bindings.TpFileIndexEntry> entries,
    )
    operation,
  ) {
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'must not be negative');
    }
    final entryCapacity = limit;
    final stringCapacity = _kDefaultStringBufferBytes;
    final strings = calloc<ffi.Uint8>(stringCapacity);
    final entries = calloc<bindings.TpFileIndexEntry>(entryCapacity);
    final chunk = calloc<bindings.TpFileIndexChunk>()
      ..ref.string_buf = strings.cast<ffi.Char>()
      ..ref.string_buf_cap = stringCapacity
      ..ref.entries = entries
      ..ref.entries_cap = entryCapacity;
    try {
      return operation(chunk, strings, entries);
    } finally {
      calloc.free(chunk);
      calloc.free(entries);
      calloc.free(strings);
    }
  }

  void _checkQueryStatus(int status) {
    if (status < 0) {
      throw StateError('file index query failed with code $status');
    }
  }

  String _readCStringAt(
    ffi.Pointer<ffi.Uint8> buffer,
    ffi.Pointer<ffi.Char> ptr,
  ) {
    if (ptr == ffi.nullptr) return '';
    return (buffer + (ptr.address - buffer.address))
        .cast<Utf8>()
        .toDartString();
  }
}

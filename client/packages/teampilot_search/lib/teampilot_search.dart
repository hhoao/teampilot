/// Ripgrep-based content search engine for TeamPilot.
///
/// The Rust core (`rust/`) is compiled into a native asset by
/// `hook/build.dart`; bindings live in
/// `teampilot_search_bindings_generated.dart`.
library;

export 'src/fallback_search_engine.dart' show fallbackSearch, kFallbackIgnoredDirNames, kFallbackMaxLineBytes;
export 'src/file_index.dart';
export 'src/search_file_reader.dart' show SearchFileReader, SearchDirEntry;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'teampilot_search_bindings_generated.dart' as bindings;

/// Version string reported by the Rust core, e.g. `teampilot_search/0.1.0`.
String engineVersion() {
  final ptr = bindings.tp_search_version();
  return ptr.cast<Utf8>().toDartString();
}

/// Search options, mirroring VS Code search semantics.
class TpSearchOptions {
  const TpSearchOptions({
    required this.pattern,
    this.isRegex = true,
    this.caseSensitive = false,
    this.smartCase = false,
    this.useGitignore = true,
    this.filesToInclude = const [],
    this.filesToExclude = const [],
    this.maxFileSize = 10 * 1024 * 1024,
    this.maxResults = 2000,
  });

  final String pattern;
  final bool isRegex;
  final bool caseSensitive;
  final bool smartCase;
  final bool useGitignore;
  final List<String> filesToInclude;
  final List<String> filesToExclude;
  final int? maxFileSize;
  final int? maxResults;
}

/// One matching line, with the match range in [matchStart, matchEnd)
/// (character offsets within [lineText]).
class TpSearchMatch {
  const TpSearchMatch({
    required this.path,
    required this.relativePath,
    required this.lineNumber,
    required this.lineText,
    required this.matchStart,
    required this.matchEnd,
  });

  final String path;
  final String relativePath;

  /// 1-based line number.
  final int lineNumber;
  final String lineText;

  /// Character offset of the match within [lineText].
  final int matchStart;
  final int matchEnd;
}

/// Pre-validates [options.pattern]; returns null for an invalid regex.
RegExp? compilePattern(TpSearchOptions options) {
  if (!options.isRegex) return null;
  try {
    return RegExp(
      options.pattern,
      caseSensitive: options.caseSensitive,
    );
  } on FormatException {
    return null;
  }
}

const int _kStatusMore = 0;
const int _kStatusDone = 1;
const int _kStatusCancelled = 2;
const int _kErrInvalidPattern = -1;
const int _kErrRootUnreadable = -2;

/// Chunk sizes used for the FFI calls.
const int _kMaxChunkMatches = 256;
const int _kMaxChunkBytes = 64 * 1024;

int _byteToCharOffset(String line, int byteOffset) {
  final bytes = utf8.encode(line);
  return utf8.decode(bytes.sublist(0, byteOffset), allowMalformed: true).length;
}

/// Rust-backed content search engine.
class TpSearchEngine {
  ffi.Pointer<bindings.TpSearchHandle>? _handle;

  /// True when [path] is directly readable by this process (local disk or a
  /// Windows `\\wsl$\...` UNC path), i.e. the Rust engine can search it.
  bool supportsPath(String path) {
    try {
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  /// Cancels the active [search] stream (if any).
  void cancel() {
    final h = _handle;
    if (h != null) {
      bindings.tp_search_cancel(h);
    }
  }

  /// Searches [root] for [options.pattern], streaming matches.
  ///
  /// Throws [StateError] when [root] is not readable by this process;
  /// emits a [FormatException] when the pattern is an invalid regex.
  Stream<TpSearchMatch> search(String root, TpSearchOptions options) async* {
    final pattern = compilePattern(options);
    if (pattern == null && options.isRegex) {
      throw FormatException('invalid regex: ${options.pattern}');
    }
    if (!supportsPath(root)) {
      throw StateError('path not readable locally: $root');
    }

    final handle = _open(root, options);
    _handle = handle;
    try {
      final matchesBuf = calloc<bindings.TpSearchMatch>(_kMaxChunkMatches);
      final stringsBuf = calloc<ffi.Uint8>(_kMaxChunkBytes);
      final chunk = calloc<bindings.TpSearchChunk>(1);
      chunk.ref
        ..string_buf = stringsBuf.cast<ffi.Char>()
        ..string_buf_cap = _kMaxChunkBytes
        ..matches = matchesBuf
        ..matches_cap = _kMaxChunkMatches;
      try {
        while (true) {
          chunk.ref
            ..string_buf_len = 0
            ..matches_len = 0
            ..truncated = 0;
          final status = bindings.tp_search_next(handle, chunk);
          if (status == _kStatusCancelled) break;
          if (status < 0) {
            throw StateError('search failed with code $status');
          }
          final count = chunk.ref.matches_len;
          for (var i = 0; i < count; i++) {
            final m = matchesBuf[i];
            final lineText = _readCStringAt(stringsBuf, m.line_text);
            yield TpSearchMatch(
              path: _readCStringAt(stringsBuf, m.path),
              relativePath: _readCStringAt(stringsBuf, m.relative_path),
              lineNumber: m.line_number,
              lineText: lineText,
              matchStart: _byteToCharOffset(lineText, m.match_start),
              matchEnd: _byteToCharOffset(lineText, m.match_end),
            );
          }
          if (status == _kStatusDone) break;
          if (status == _kStatusMore && count == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      } finally {
        calloc.free(matchesBuf);
        calloc.free(stringsBuf);
        calloc.free(chunk);
      }
    } finally {
      bindings.tp_search_free(handle);
      _handle = null;
    }
  }

  ffi.Pointer<bindings.TpSearchHandle> _open(String root, TpSearchOptions options) {
    final cRoot = root.toNativeUtf8();
    final cPattern = options.pattern.toNativeUtf8();
    final includePtrs = options.filesToInclude.map((s) => s.toNativeUtf8()).toList();
    final excludePtrs = options.filesToExclude.map((s) => s.toNativeUtf8()).toList();
    final includes = calloc<ffi.Pointer<ffi.Char>>(includePtrs.length);
    final excludes = calloc<ffi.Pointer<ffi.Char>>(excludePtrs.length);
    for (var i = 0; i < includePtrs.length; i++) {
      includes[i] = includePtrs[i].cast<ffi.Char>();
    }
    for (var i = 0; i < excludePtrs.length; i++) {
      excludes[i] = excludePtrs[i].cast<ffi.Char>();
    }
    final config = calloc<bindings.TpSearchConfig>()
      ..ref.root = cRoot.cast<ffi.Char>()
      ..ref.pattern = cPattern.cast<ffi.Char>()
      ..ref.is_regex = options.isRegex ? 1 : 0
      ..ref.case_sensitive = options.caseSensitive ? 1 : 0
      ..ref.smart_case = options.smartCase ? 1 : 0
      ..ref.use_gitignore = options.useGitignore ? 1 : 0
      ..ref.files_to_include = includes
      ..ref.files_to_include_count = includePtrs.length
      ..ref.files_to_exclude = excludes
      ..ref.files_to_exclude_count = excludePtrs.length
      ..ref.max_file_size = options.maxFileSize ?? 0
      ..ref.max_results = options.maxResults ?? 0
      ..ref.max_chunk_matches = _kMaxChunkMatches
      ..ref.max_chunk_bytes = _kMaxChunkBytes;

    final out = calloc<ffi.Pointer<bindings.TpSearchHandle>>(1);
    try {
      final status = bindings.tp_search_new(config, out);
      if (status == _kErrInvalidPattern) {
        throw FormatException('invalid regex: ${options.pattern}');
      }
      if (status == _kErrRootUnreadable) {
        throw StateError('root unreadable: $root');
      }
      if (status < 0) {
        throw StateError('search init failed with code $status');
      }
      return out.value;
    } finally {
      calloc.free(config);
      calloc.free(out);
      for (final p in includePtrs) {
        malloc.free(p);
      }
      for (final p in excludePtrs) {
        malloc.free(p);
      }
      malloc.free(cRoot);
      malloc.free(cPattern);
      calloc.free(includes);
      calloc.free(excludes);
    }
  }

  /// Reads the NUL-terminated C string at [ptr] from within [buf].
  ///
  /// [ptr] must point into [buf] (chunk strings are packed into the
  /// caller-provided `string_buf` and are only valid until the next
  /// `tp_search_next`/`tp_search_free` call). `sizeOf<Char>() == 1`, so the
  /// byte offset from [buf.address] equals the element offset for pointer
  /// arithmetic.
  String _readCStringAt(ffi.Pointer<ffi.Uint8> buf, ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) return '';
    final offset = ptr.address - buf.address;
    return (buf + offset).cast<Utf8>().toDartString();
  }
}

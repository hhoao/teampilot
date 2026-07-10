/// Viewport-first Tree-sitter bindings for TeamPilot's editor platform.
///
/// The whole tree-sitter core plus the bundled grammars are statically linked
/// into a single native asset (see `hook/build.dart`). This library exposes a
/// small, Dart-idiomatic wrapper over the generated FFI bindings.
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'teampilot_tree_sitter_bindings_generated.dart' as bindings;

/// A loaded tree-sitter grammar (opaque `TSLanguage *`).
///
/// Languages are static, immortal singletons owned by the native library, so
/// there is nothing to dispose.
class TsLanguage {
  const TsLanguage._(this.pointer);

  /// The underlying `TSLanguage *`.
  final ffi.Pointer<bindings.TSLanguage> pointer;

  /// The bundled JSON grammar.
  static TsLanguage json() => TsLanguage._(bindings.tp_ts_language_json());
}

/// A parsed syntax tree (`TSTree *`). Call [dispose] when done.
class TsTree {
  TsTree._(this.pointer);

  /// The underlying `TSTree *`.
  final ffi.Pointer<bindings.TSTree> pointer;

  bool _disposed = false;

  /// Frees the native tree. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bindings.ts_tree_delete(pointer);
  }
}

/// A byte/point range edit applied to a tree before incremental re-parsing.
class TsInputEdit {
  const TsInputEdit({
    required this.startByte,
    required this.oldEndByte,
    required this.newEndByte,
    this.startPoint = TsPoint.zero,
    this.oldEndPoint = TsPoint.zero,
    this.newEndPoint = TsPoint.zero,
  });

  final int startByte;
  final int oldEndByte;
  final int newEndByte;
  final TsPoint startPoint;
  final TsPoint oldEndPoint;
  final TsPoint newEndPoint;
}

/// A zero-based (row, column-in-bytes) position.
class TsPoint {
  const TsPoint(this.row, this.column);

  static const TsPoint zero = TsPoint(0, 0);

  final int row;
  final int column;
}

/// Wraps a `TSParser *`. Not safe to share across isolates. Call [dispose].
class TsParser {
  TsParser() : _parser = bindings.ts_parser_new();

  final ffi.Pointer<bindings.TSParser> _parser;
  bool _disposed = false;

  /// Sets the grammar used for subsequent parses.
  void setLanguage(TsLanguage language) {
    final ok = bindings.ts_parser_set_language(_parser, language.pointer);
    if (!ok) {
      throw StateError(
        'ts_parser_set_language failed: grammar ABI is incompatible with the '
        'linked tree-sitter runtime.',
      );
    }
  }

  /// Parses [bytes] (UTF-8) into a new [TsTree].
  ///
  /// When [oldTree] is supplied (after applying [edit]s), tree-sitter reuses
  /// unchanged subtrees for incremental parsing.
  TsTree parseUtf8(Uint8List bytes, {TsTree? oldTree}) {
    final length = bytes.length;
    final buffer = malloc<ffi.Char>(length == 0 ? 1 : length);
    try {
      if (length > 0) {
        buffer.cast<ffi.Uint8>().asTypedList(length).setAll(0, bytes);
      }
      final treePtr = bindings.ts_parser_parse_string(
        _parser,
        oldTree?.pointer ?? ffi.nullptr,
        buffer,
        length,
      );
      if (treePtr == ffi.nullptr) {
        throw StateError('ts_parser_parse_string returned null.');
      }
      return TsTree._(treePtr);
    } finally {
      malloc.free(buffer);
    }
  }

  /// Records an [edit] on [tree] so a follow-up [parseUtf8] can reuse subtrees.
  void edit(TsTree tree, TsInputEdit edit) {
    final native = calloc<bindings.TSInputEdit>();
    try {
      final ref = native.ref;
      ref.start_byte = edit.startByte;
      ref.old_end_byte = edit.oldEndByte;
      ref.new_end_byte = edit.newEndByte;
      _writePoint(ref.start_point, edit.startPoint);
      _writePoint(ref.old_end_point, edit.oldEndPoint);
      _writePoint(ref.new_end_point, edit.newEndPoint);
      bindings.ts_tree_edit(tree.pointer, native);
    } finally {
      calloc.free(native);
    }
  }

  /// Frees the native parser. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bindings.ts_parser_delete(_parser);
  }

  static void _writePoint(bindings.TSPoint dst, TsPoint src) {
    dst.row = src.row;
    dst.column = src.column;
  }
}

/// A single capture returned by [TsQuery.captures].
class TsCapture {
  const TsCapture({
    required this.name,
    required this.startByte,
    required this.endByte,
  });

  /// Capture name without the leading `@` (e.g. `string`).
  final String name;
  final int startByte;
  final int endByte;
}

/// A compiled tree-sitter query (`TSQuery *`). Call [dispose].
class TsQuery {
  TsQuery._(this._query);

  /// Compiles [source] against [language].
  ///
  /// Throws [ArgumentError] if the query source is malformed.
  factory TsQuery(TsLanguage language, String source) {
    final sourceBytes = utf8.encode(source);
    final sourcePtr = malloc<ffi.Char>(
      sourceBytes.isEmpty ? 1 : sourceBytes.length,
    );
    final errorOffset = calloc<ffi.Uint32>();
    final errorType = calloc<ffi.UnsignedInt>();
    try {
      if (sourceBytes.isNotEmpty) {
        sourcePtr
            .cast<ffi.Uint8>()
            .asTypedList(sourceBytes.length)
            .setAll(0, sourceBytes);
      }
      final query = bindings.ts_query_new(
        language.pointer,
        sourcePtr,
        sourceBytes.length,
        errorOffset,
        errorType,
      );
      if (query == ffi.nullptr) {
        throw ArgumentError(
          'Invalid tree-sitter query (error type ${errorType.value} at byte '
          'offset ${errorOffset.value}).',
        );
      }
      return TsQuery._(query);
    } finally {
      malloc.free(sourcePtr);
      calloc.free(errorOffset);
      calloc.free(errorType);
    }
  }

  final ffi.Pointer<bindings.TSQuery> _query;
  bool _disposed = false;

  /// Runs the query over [tree], restricted to `[startByte, endByte)`.
  ///
  /// Restricting the byte range is what makes highlighting viewport-first: only
  /// nodes intersecting the requested window are matched.
  List<TsCapture> captures(
    TsTree tree, {
    required int startByte,
    required int endByte,
  }) {
    final cursor = bindings.ts_query_cursor_new();
    final matchPtr = calloc<bindings.TSQueryMatch>();
    final results = <TsCapture>[];
    try {
      bindings.ts_query_cursor_set_byte_range(cursor, startByte, endByte);
      bindings.ts_query_cursor_exec(
        cursor,
        _query,
        bindings.ts_tree_root_node(tree.pointer),
      );
      while (bindings.ts_query_cursor_next_match(cursor, matchPtr)) {
        final match = matchPtr.ref;
        for (var i = 0; i < match.capture_count; i++) {
          final capture = match.captures[i];
          results.add(
            TsCapture(
              name: _captureName(capture.index),
              startByte: bindings.ts_node_start_byte(capture.node),
              endByte: bindings.ts_node_end_byte(capture.node),
            ),
          );
        }
      }
      return results;
    } finally {
      calloc.free(matchPtr);
      bindings.ts_query_cursor_delete(cursor);
    }
  }

  /// Frees the native query. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bindings.ts_query_delete(_query);
  }

  String _captureName(int captureId) {
    final lengthPtr = calloc<ffi.Uint32>();
    try {
      final namePtr = bindings.ts_query_capture_name_for_id(
        _query,
        captureId,
        lengthPtr,
      );
      if (namePtr == ffi.nullptr) return '';
      return namePtr.cast<Utf8>().toDartString(length: lengthPtr.value);
    } finally {
      calloc.free(lengthPtr);
    }
  }
}

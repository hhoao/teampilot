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

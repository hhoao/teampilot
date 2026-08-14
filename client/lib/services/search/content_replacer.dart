import 'dart:convert';

import 'package:teampilot_search/teampilot_search.dart';

import '../io/filesystem.dart';

/// Applies search-result replacements to a file by writing it back through
/// [Filesystem] (works for local and SFTP). No undo: callers confirm first.
class ContentReplacer {
  ContentReplacer({required Filesystem fs}) : _fs = fs;

  final Filesystem _fs;

  /// Replaces [matches] (same file, ascending line order) in [path] and
  /// writes the file back. [TpSearchMatch.matchStart/End] are UTF-16 code
  /// unit offsets usable directly as String indices. Returns the number of
  /// replacements applied (== matches.length).
  Future<int> replaceAllInFile({
    required String path,
    required List<TpSearchMatch> matches,
    required String replacement,
  }) async {
    if (matches.isEmpty) return 0;
    final text = await _fs.readString(path);
    if (text == null) return 0;

    // (lineStart, lineEnd) per line — lineEnd includes the terminator.
    final bounds = _lineBounds(text);

    // Build (start, end) in full-text coordinates, bottom-up to stay valid.
    final edits = <(int, int)>[];
    for (final m in matches) {
      if (m.lineNumber < 1 || m.lineNumber > bounds.length) continue;
      final (start, end) = bounds[m.lineNumber - 1];
      if (m.matchStart < 0 || m.matchEnd < m.matchStart) continue;
      final absStart = start + m.matchStart;
      final absEnd = start + m.matchEnd;
      if (absEnd > end) continue; // line text says otherwise; skip defensively
      edits.add((absStart, absEnd));
    }
    if (edits.isEmpty) return 0;
    edits.sort((a, b) => b.$1.compareTo(a.$1));

    final sb = StringBuffer();
    var cursor = 0;
    for (final (s, e) in edits.reversed) {
      sb.write(text.substring(cursor, s));
      sb.write(replacement);
      cursor = e;
    }
    sb.write(text.substring(cursor));
    await _fs.writeString(path, sb.toString());
    return edits.length;
  }

  List<(int, int)> _lineBounds(String text) {
    final bounds = <(int, int)>[];
    var start = 0;
    for (final _ in const LineSplitter().convert(text)) {
      final end = text.indexOf('\n', start);
      final lineEnd = end == -1 ? text.length : end + 1;
      bounds.add((start, lineEnd));
      start = lineEnd;
    }
    return bounds;
  }
}

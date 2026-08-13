import '../teampilot_search.dart';
import 'search_file_reader.dart';

/// Directory names skipped wholesale during fallback traversal.
const kFallbackIgnoredDirNames = {
  '.git', '.hg', '.svn', 'node_modules', '.dart_tool', 'build',
  '.idea', '.gradle', '.next', 'dist',
};

/// Longest line whose text is kept; longer lines yield text-less matches.
const int kFallbackMaxLineBytes = 1024 * 1024;

/// Pure-Dart content search over a [SearchFileReader], used when the target
/// filesystem is not directly readable by this process (e.g. SSH/SFTP).
///
/// Mirrors [TpSearchEngine.search] semantics: case-insensitive by default,
/// hidden entries skipped, [kFallbackIgnoredDirNames] skipped, glob
/// include/exclude, [TpSearchOptions.maxFileSize] / [maxResults] caps.
Stream<TpSearchMatch> fallbackSearch(
  SearchFileReader reader,
  String root,
  TpSearchOptions options,
) async* {
  final pattern = compilePattern(options);
  if (options.isRegex && pattern == null) {
    throw FormatException('invalid regex: ${options.pattern}');
  }
  final q = options.isRegex ? options.pattern : RegExp.escape(options.pattern);
  final caseSensitive = options.caseSensitive ||
      (options.smartCase && _hasUppercase(options.pattern));
  final rx = RegExp(q, caseSensitive: caseSensitive);
  final includeGlobs = options.filesToInclude
      .map((g) => _Glob(g))
      .toList(growable: false);
  final excludeGlobs = options.filesToExclude
      .map((g) => _Glob(g))
      .toList(growable: false);

  final queue = <String>[root];
  var truncated = false;
  var matchCount = 0;

  while (queue.isNotEmpty) {
    if (truncated) break;
    final dir = queue.removeAt(0);
    final entries = await reader.listDir(dir);
    for (final entry in entries) {
      if (truncated) break;
      final name = entry.name;
      if (name.startsWith('.')) continue;
      final full = dir == root ? '$root/$name' : '$dir/$name';
      if (entry.isDirectory) {
        if (kFallbackIgnoredDirNames.contains(name)) continue;
        queue.add(full);
        continue;
      }
      final rel = full.substring(root.length + 1);
      if (includeGlobs.isNotEmpty && !includeGlobs.any((g) => g.matches(rel))) {
        continue;
      }
      if (excludeGlobs.any((g) => g.matches(rel))) continue;
      if (options.maxFileSize != null &&
          entry.size != null &&
          entry.size! > options.maxFileSize!) {
        continue;
      }
      final lines = await reader.readLines(full);
      if (lines == null) continue;
      for (var i = 0; i < lines.length; i++) {
        if (truncated) break;
        final line = lines[i];
        if (line.codeUnits.length > kFallbackMaxLineBytes) {
          matchCount++;
          yield TpSearchMatch(
            path: full,
            relativePath: rel,
            lineNumber: i + 1,
            lineText: '',
            matchStart: 0,
            matchEnd: 0,
          );
          if (options.maxResults != null && matchCount >= options.maxResults!) {
            truncated = true;
            break;
          }
          continue;
        }
        final matches = rx.allMatches(line);
        if (matches.isEmpty) continue;
        for (final m in matches) {
          matchCount++;
          yield TpSearchMatch(
            path: full,
            relativePath: rel,
            lineNumber: i + 1,
            lineText: line,
            matchStart: m.start,
            matchEnd: m.end,
          );
          if (options.maxResults != null && matchCount >= options.maxResults!) {
            truncated = true;
            break;
          }
        }
      }
    }
  }
}

/// True when [s] contains an uppercase letter (smart-case trigger).
bool _hasUppercase(String s) {
  for (final c in s.split('')) {
    if (c.toLowerCase() != c && c.toUpperCase() == c) return true;
  }
  return false;
}

/// Tiny gitignore-style glob (supports `*`, `**`, `?`, `[...]`).
class _Glob {
  _Glob(String pattern) : _rx = RegExp(_translate(pattern));

  final RegExp _rx;

  bool matches(String path) => _rx.hasMatch(path);

  static String _translate(String pattern) {
    var out = '^';
    // gitignore semantics: a pattern without `/` matches at any depth.
    if (!pattern.contains('/')) out += '(?:.*/)?';
    var chars = pattern.split('');
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      switch (c) {
        case '*':
          if (i + 1 < chars.length && chars[i + 1] == '*') {
            i++;
            out += '.*';
          } else {
            out += '[^/]*';
          }
          break;
        case '?':
          out += '[^/]';
          break;
        case '[':
          out += '[';
          break;
        case ']':
          out += ']';
          break;
        case '.':
        case '+':
        case '(':
        case ')':
        case '{':
        case '}':
        case '^':
        case r'$':
        case r'\':
          out += '\\$c';
          break;
        default:
          out += c;
      }
    }
    out += r'$';
    return out;
  }
}

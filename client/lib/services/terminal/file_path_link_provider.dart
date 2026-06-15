import 'package:flutter_alacritty/links/terminal_link_provider.dart';

import '../io/filesystem.dart';

/// Detects file paths in terminal output and (with async validation in later
/// tasks) makes only existing files clickable. Injected into TerminalView as a
/// [TerminalLinkProvider]. Path semantics + filesystem validation live here in
/// TeamPilot, keeping flutter_alacritty IO-free.
class FilePathLinkProvider extends TerminalLinkProvider {
  FilePathLinkProvider({required this.fs, required this.launchCwd});

  final Filesystem fs;
  final String launchCwd;

  // Matches an optional anchor (./ ../ / or a Windows drive), then path-ish
  // segments, then an optional :line[:col] suffix.
  static final RegExp _pattern = RegExp(
    r'(?:\.{1,2}/|/|[A-Za-z]:[\\/])?'
    r'[\w.\-]+(?:[\\/][\w.\-]+)*'
    r'(?::\d+(?::\d+)?)?',
  );

  @override
  Iterable<LinkSpan> scan(String lineText) sync* {
    for (final m in _pattern.allMatches(lineText)) {
      final raw = m.group(0)!;
      if (!_looksLikePath(raw)) continue;
      yield LinkSpan(start: m.start, end: m.end, payload: raw);
    }
  }

  /// Shape heuristic to cut obvious non-paths before the (later) fs check.
  bool _looksLikePath(String s) {
    final core = s.split(':').first; // ignore :line[:col] for the shape test
    if (core.contains('/') || core.contains(r'\')) return true;
    if (core.startsWith('./') || core.startsWith('../')) return true;
    // Single token: require a real file extension, and reject version-ish runs.
    final ext = RegExp(r'\.[A-Za-z][A-Za-z0-9]{0,8}$');
    return ext.hasMatch(core) && !RegExp(r'^\d+(\.\d+)+$').hasMatch(core);
  }

  @override
  bool isEnabled(LinkSpan span) => false; // Task 9 adds real validation
}

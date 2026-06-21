/// How a projected path is spelled as a *reference* inside a CLI's input box.
///
/// TeamPilot's PTYs run agent CLIs, not raw shells, so this is about producing a
/// clean, single-token path the agent reads — not shell-execution safety. The
/// enum is the extension seam: a CLI that wants `@file` mentions or PowerShell
/// quoting adds a value here, picked via its terminal-behavior capability.
enum PathQuoting {
  /// Wrap in single quotes only when the path contains characters that would
  /// otherwise split it into multiple tokens (spaces, quotes, shell glyphs).
  posixQuoteIfNeeded,

  /// Emit the path verbatim, no quoting.
  none,
}

/// Renders a projected absolute path as input-box text per a [PathQuoting].
/// Pure; unit-tested in isolation.
class PathReferenceFormatter {
  const PathReferenceFormatter();

  String format(String path, PathQuoting quoting) {
    switch (quoting) {
      case PathQuoting.none:
        return path;
      case PathQuoting.posixQuoteIfNeeded:
        return _posixQuoteIfNeeded(path);
    }
  }

  // Single-quote is the safest POSIX wrapper: everything inside is literal
  // except a single quote itself, which is escaped as the classic `'\''`.
  static final RegExp _needsQuote = RegExp(r'''[^A-Za-z0-9_@%+=:,./\\-]''');

  String _posixQuoteIfNeeded(String path) {
    if (path.isEmpty) return "''";
    if (!_needsQuote.hasMatch(path)) return path;
    return "'${path.replaceAll("'", r"'\''")}'";
  }
}

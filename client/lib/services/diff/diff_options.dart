/// Options that influence how lines are compared (not how they are rendered).
///
/// Normalization only affects equality during diffing; the [DiffRow] text always
/// carries the original, unmodified line so the UI can render it verbatim.
class DiffOptions {
  const DiffOptions({
    this.ignoreWhitespace = false,
    this.ignoreCase = false,
  });

  /// Collapse runs of whitespace and trim both ends before comparing lines.
  final bool ignoreWhitespace;

  /// Compare lines case-insensitively.
  final bool ignoreCase;

  static const DiffOptions none = DiffOptions();

  /// Returns the comparison key for [line] under these options.
  String normalize(String line) {
    var result = line;
    if (ignoreWhitespace) {
      result = result.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    if (ignoreCase) {
      result = result.toLowerCase();
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is DiffOptions &&
      other.ignoreWhitespace == ignoreWhitespace &&
      other.ignoreCase == ignoreCase;

  @override
  int get hashCode => Object.hash(ignoreWhitespace, ignoreCase);
}

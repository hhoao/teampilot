/// A single styled run within one line of source text.
///
/// Offsets are UTF-16 **code units relative to the start of the line**, so a
/// [TokenSpan] can be applied directly to a Dart `String` line without any
/// further byte conversion (the UTF-8 byte ranges from tree-sitter are mapped
/// back to code units by `DocumentSession` before spans are built).
class TokenSpan {
  const TokenSpan({
    required this.start,
    required this.length,
    required this.scope,
  });

  /// Code-unit offset of the run's first character on its line.
  final int start;

  /// Length of the run in code units. Always `> 0`.
  final int length;

  /// TextMate-style scope name, mapped from a tree-sitter capture name.
  ///
  /// For now the capture name is used verbatim as the scope (e.g. a `@string`
  /// capture yields scope `string`), which `EditorSyntaxTheme.styleFor`
  /// resolves to a [TextStyle].
  final String scope;

  /// Code-unit offset one past the end of the run.
  int get end => start + length;

  @override
  bool operator ==(Object other) =>
      other is TokenSpan &&
      other.start == start &&
      other.length == length &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(start, length, scope);

  @override
  String toString() => 'TokenSpan(start: $start, length: $length, scope: $scope)';
}

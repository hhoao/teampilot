/// Metadata for a single tree-sitter backed language: how to recognize a
/// file path as belonging to this language, and where its grammar/query
/// assets live. Packs carry no highlighting logic themselves; they are
/// looked up via [LanguageRegistry] and consumed by `DocumentSession`.
class LanguagePack {
  const LanguagePack({
    required this.id,
    required this.extensions,
    required this.grammarId,
    required this.highlightsAsset,
    this.filenames = const {},
  });

  /// Stable identifier, e.g. `json`, `dart`. Used for grammar cache keys
  /// and as the fallback "language id" surfaced to the UI.
  final String id;

  /// Lowercase, no leading dot, e.g. `{'json'}`.
  final Set<String> extensions;

  /// Exact basenames matched before falling back to [extensions], e.g.
  /// `{'Dockerfile'}`. Empty for packs that only match by extension.
  final Set<String> filenames;

  /// Identifier passed to the native tree-sitter binding to select the
  /// compiled grammar (e.g. `tp_ts_language_json`).
  final String grammarId;

  /// Asset path to this pack's `highlights.scm` query source.
  final String highlightsAsset;
}

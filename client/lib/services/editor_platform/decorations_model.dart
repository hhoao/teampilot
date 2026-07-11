/// Reserved layer ids for non-syntax decorations that will eventually
/// overlay a `DocumentSession` (search matches, code folds, diagnostics).
///
/// This phase ships **no decorations**: `DocumentSession` only produces
/// syntax [TokenSpan]s. The model exists so the platform layer's shape
/// matches the design doc ahead of that future work.
enum DecorationLayer { search, fold, diagnostic }

/// Empty shell for a future per-document decoration store, keyed by
/// [DecorationLayer]. No built-in pack or session populates this yet.
class DecorationsModel {
  const DecorationsModel();
}

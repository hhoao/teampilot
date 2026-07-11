/// Reserved marker for language-server-style features (hover, completion,
/// definition, diagnostics) that a [LanguagePack] may expose in a later
/// phase.
///
/// Out of scope this phase: no LSP client, no network calls, no built-in
/// pack implements this. Highlighting and decorations never depend on a
/// [LanguageFeatures] existing — the type exists only so the platform
/// layer's shape matches the design doc ahead of that future work.
abstract class LanguageFeatures {
  // Reserved: hover / completion / definition / diagnostics.
}

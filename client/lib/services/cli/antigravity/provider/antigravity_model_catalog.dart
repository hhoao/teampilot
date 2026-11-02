import '../../../../models/app_provider_config.dart';

/// Antigravity model ids. [fallback] is the documented catalog used when the
/// CLI's live list is unavailable; [parseModels] reads `agy models` output
/// (first column of each non-empty line).
///
/// The ACP adapter's `model` config ids are collapsed: thinking effort is a
/// separate option (`thinking_level`), so the catalog strips the CLI's
/// `-high` / `-medium` / `-low` suffixes. Until that option is wired, the
/// effort pickers stay hidden.
abstract final class AntigravityModelCatalog {
  const AntigravityModelCatalog._();

  static const fallback = <String>[
    'gemini-4-argon',
    'gemini-3.8-flash',
    'gemini-3.7-flash',
    'gemini-3.6-flash',
    'gemini-3.1-pro',
  ];

  /// Strips a trailing CLI effort suffix so a saved/seeded slug maps to the
  /// adapter's collapsed model id.
  static String collapse(String modelId) => modelId.trim().replaceFirst(
    RegExp(r'-(?:high|medium|low)$', caseSensitive: false),
    '',
  );

  static List<String> parseModels(String stdout) => [
    for (final line in stdout.split('\n'))
      if (line.trim().isNotEmpty) line.trim().split(RegExp(r'\s+')).first,
  ];

  static List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => fallback;
}

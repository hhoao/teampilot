import '../../../../models/app_provider_config.dart';

/// Antigravity model ids. [fallback] is the documented catalog used when the
/// CLI's live list is unavailable; [parseModels] reads `agy models` output
/// (first column of each non-empty line).
abstract final class AntigravityModelCatalog {
  const AntigravityModelCatalog._();

  static const fallback = <String>[
    'gemini-4-argon-high',
    'gemini-4-argon-medium',
    'gemini-3.8-flash-high',
    'gemini-3.8-flash-medium',
    'gemini-3.7-flash-high',
    'gemini-3.7-flash-medium',
    'gemini-3.6-flash-high',
    'gemini-3.6-flash-medium',
    'gemini-3.1-pro-high',
  ];

  static List<String> parseModels(String stdout) => [
    for (final line in stdout.split('\n'))
      if (line.trim().isNotEmpty) line.trim().split(RegExp(r'\s+')).first,
  ];

  static List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => fallback;
}

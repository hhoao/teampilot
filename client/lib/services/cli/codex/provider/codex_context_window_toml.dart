/// Patches `model_context_window` in Codex `config.toml` bodies.
///
/// Codex reads the window from the top-level key; the per-model value only
/// overrides it when one is configured.
abstract final class CodexContextWindowToml {
  CodexContextWindowToml._();

  static String applyContextWindow(String toml, int tokens) {
    if (tokens <= 0) return toml;
    final line = 'model_context_window = $tokens';
    final pattern = RegExp(
      r'^model_context_window\s*=\s*\d+\s*$',
      multiLine: true,
    );
    if (pattern.hasMatch(toml)) {
      return toml.replaceFirst(pattern, line);
    }
    final modelPattern = RegExp(r'^model\s*=\s*".*"$', multiLine: true);
    if (modelPattern.hasMatch(toml)) {
      return toml.replaceFirst(
        modelPattern,
        '${modelPattern.stringMatch(toml)}\n$line',
      );
    }
    if (toml.trim().isEmpty) return line;
    return '$toml\n$line';
  }
}

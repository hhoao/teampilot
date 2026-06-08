/// Patches `model_reasoning_effort` in Codex `config.toml` bodies.
abstract final class CodexEffortToml {
  CodexEffortToml._();

  static String applyReasoningEffort(String toml, String effort) {
    final trimmed = effort.trim();
    if (trimmed.isEmpty) return toml;
    final line = 'model_reasoning_effort = "$trimmed"';
    final pattern = RegExp(
      r'^model_reasoning_effort\s*=\s*".*"$',
      multiLine: true,
    );
    if (pattern.hasMatch(toml)) {
      return toml.replaceFirst(pattern, line);
    }
    final modelPattern = RegExp(r'^model\s*=\s*".*"$', multiLine: true);
    if (modelPattern.hasMatch(toml)) {
      return toml.replaceFirst(modelPattern, '${modelPattern.stringMatch(toml)}\n$line');
    }
    if (toml.trim().isEmpty) return line;
    return '$toml\n$line';
  }
}

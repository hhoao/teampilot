import 'package:path/path.dart' as p;

enum LlmConfigPathSource { userOverride, defaultPath }

class ResolvedLlmConfigPath {
  const ResolvedLlmConfigPath(this.path, this.source);

  final String path;
  final LlmConfigPathSource source;
}

/// Resolves the active LLM config path.
///
/// Priority:
///   1. [userOverride] (with `~` expansion; relative paths resolved against
///      [currentDirectory]).
///   2. CLI install dir: `<cliExecutable>/../llm/llm_config.json`.
///
/// If neither is available (no override and CLI not located), returns an
/// empty path so callers can show an inert UI state and the user can set a
/// custom path manually.
ResolvedLlmConfigPath resolveLlmConfigPath({
  required String? userOverride,
  required String currentDirectory,
  required String? homeDirectory,
  required String? cliExecutablePath,
}) {
  final raw = userOverride?.trim() ?? '';
  if (raw.isNotEmpty) {
    final expanded = _expandHome(raw, homeDirectory);
    final absolute = p.isAbsolute(expanded)
        ? expanded
        : p.absolute(p.join(currentDirectory, expanded));
    return ResolvedLlmConfigPath(
        p.normalize(absolute), LlmConfigPathSource.userOverride);
  }

  final cliCandidate = _cliInstallCandidate(cliExecutablePath);
  return ResolvedLlmConfigPath(
    cliCandidate ?? '',
    LlmConfigPathSource.defaultPath,
  );
}

String? _cliInstallCandidate(String? cliExecutablePath) {
  if (cliExecutablePath == null || cliExecutablePath.isEmpty) return null;
  // CLI lives at <install>/dist/flashskyai; config sits at <install>/llm/...
  final cliDir = p.dirname(p.absolute(cliExecutablePath));
  return p.normalize(p.join(cliDir, '..', 'llm', 'llm_config.json'));
}

String _expandHome(String input, String? home) {
  if (input != '~' && !input.startsWith('~/') && !input.startsWith(r'~\')) {
    return input;
  }
  if (home == null || home.isEmpty) return input;
  if (input == '~') return home;
  return p.join(home, input.substring(2));
}

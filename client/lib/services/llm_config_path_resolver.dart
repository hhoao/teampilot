import 'dart:io';

import 'package:path/path.dart' as p;

enum LlmConfigPathSource { userOverride, defaultPath }

class ResolvedLlmConfigPath {
  const ResolvedLlmConfigPath(this.path, this.source);

  final String path;
  final LlmConfigPathSource source;
}

typedef FileExistsCheck = bool Function(String path);

/// Resolves the active LLM config path.
///
/// Priority:
///   1. [userOverride] (with `~` expansion; relative paths resolved against
///      [currentDirectory]).
///   2. CLI install dir: `<cliExecutable>/../../llm/llm_config.json` if it
///      exists.
///   3. Home fallback: `<home>/.flashskyai/llm/llm_config.json` if it exists.
///   4. If neither default candidate exists, prefer the CLI candidate when
///      known so the file lands where the CLI looks first; otherwise return
///      the home candidate.
ResolvedLlmConfigPath resolveLlmConfigPath({
  required String? userOverride,
  required String currentDirectory,
  required String? homeDirectory,
  required String? cliExecutablePath,
  FileExistsCheck? fileExistsSync,
}) {
  final exists = fileExistsSync ?? (path) => File(path).existsSync();

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
  if (cliCandidate != null && exists(cliCandidate)) {
    return ResolvedLlmConfigPath(cliCandidate, LlmConfigPathSource.defaultPath);
  }

  final homeCandidate = _homeCandidate(homeDirectory);
  if (homeCandidate != null && exists(homeCandidate)) {
    return ResolvedLlmConfigPath(homeCandidate, LlmConfigPathSource.defaultPath);
  }

  // Neither file exists. Prefer the CLI candidate so a future save lands where
  // the CLI looks first; fall back to the home candidate or empty string.
  return ResolvedLlmConfigPath(
    cliCandidate ?? homeCandidate ?? '',
    LlmConfigPathSource.defaultPath,
  );
}

String? _cliInstallCandidate(String? cliExecutablePath) {
  if (cliExecutablePath == null || cliExecutablePath.isEmpty) return null;
  // CLI lives at <install>/dist/flashskyai; config sits at <install>/llm/...
  final cliDir = p.dirname(p.absolute(cliExecutablePath));
  return p.normalize(p.join(cliDir, '..', 'llm', 'llm_config.json'));
}

String? _homeCandidate(String? homeDirectory) {
  if (homeDirectory == null || homeDirectory.isEmpty) return null;
  return p.normalize(
      p.join(homeDirectory, '.flashskyai', 'llm', 'llm_config.json'));
}

String _expandHome(String input, String? home) {
  if (input != '~' && !input.startsWith('~/') && !input.startsWith(r'~\')) {
    return input;
  }
  if (home == null || home.isEmpty) return input;
  if (input == '~') return home;
  return p.join(home, input.substring(2));
}

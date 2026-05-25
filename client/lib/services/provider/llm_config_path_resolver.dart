import 'package:path/path.dart' as p;

import '../cli/cli_invocation.dart';

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
  bool usePosixPaths = false,
}) {
  final posixPaths = _usesPosixPaths(
    usePosixPaths: usePosixPaths,
    cliExecutablePath: cliExecutablePath,
  );
  final ctx = posixPaths ? p.Context(style: p.Style.posix) : p.context;

  final raw = userOverride?.trim() ?? '';
  if (raw.isNotEmpty) {
    final expanded = _expandHome(raw, homeDirectory, ctx);
    final absolute = _pathIsAbsolute(expanded, posixOnly: posixPaths)
        ? expanded
        : ctx.normalize(ctx.absolute(ctx.join(currentDirectory, expanded)));
    return ResolvedLlmConfigPath(
      ctx.normalize(absolute),
      LlmConfigPathSource.userOverride,
    );
  }

  final cliCandidate = _cliInstallCandidate(cliExecutablePath, ctx);
  return ResolvedLlmConfigPath(
    cliCandidate ?? '',
    LlmConfigPathSource.defaultPath,
  );
}

bool _usesPosixPaths({
  required bool usePosixPaths,
  required String? cliExecutablePath,
}) {
  if (usePosixPaths) return true;
  final cli = cliExecutablePath?.trim() ?? '';
  return _linuxExecutablePathForInstallLayout(cli) != null;
}

bool _pathIsAbsolute(String path, {required bool posixOnly}) {
  if (posixOnly) return path.startsWith('/');
  return p.isAbsolute(path);
}

String? _cliInstallCandidate(String? cliExecutablePath, p.Context ctx) {
  if (cliExecutablePath == null || cliExecutablePath.isEmpty) return null;
  // CLI lives at <install>/dist/flashskyai; config sits at <install>/llm/...
  final trimmed = cliExecutablePath.trim();
  final linuxExe = _linuxExecutablePathForInstallLayout(trimmed);
  if (linuxExe != null) {
    final cliDir = ctx.dirname(linuxExe);
    return ctx.normalize(ctx.join(cliDir, '..', 'llm', 'llm_config.json'));
  }
  final cliDir = ctx.dirname(ctx.absolute(trimmed));
  return ctx.normalize(ctx.join(cliDir, '..', 'llm', 'llm_config.json'));
}

/// When [executable] is a Windows launch line `wsl.exe /path/to/flashskyai`,
/// returns `/path/to/flashskyai` for layout rules. Otherwise null.
String? _linuxExecutablePathForInstallLayout(String executable) {
  final parts = CliInvocation.splitCommand(executable);
  if (parts.length < 2) return null;
  final name = parts.first.split(RegExp(r'[\\/]')).last.toLowerCase();
  if (name != 'wsl' && name != 'wsl.exe') return null;
  return parts[1];
}

String _expandHome(String input, String? home, p.Context ctx) {
  if (input != '~' && !input.startsWith('~/') && !input.startsWith(r'~\')) {
    return input;
  }
  if (home == null || home.isEmpty) return input;
  if (input == '~') return home;
  return ctx.join(home, input.substring(2));
}

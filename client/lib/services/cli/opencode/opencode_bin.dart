import 'package:path/path.dart' as p;

import '../cli_version_probe.dart';

/// Official OpenCode v2 binary path from https://opencode.ai/v2/install.
String? opencodeOfficialExecutablePath({
  required String? homeDirectory,
  required bool isWindows,
}) {
  final home = homeDirectory?.trim() ?? '';
  if (home.isEmpty) return null;
  final context = isWindows ? p.windows : p.posix;
  final name = isWindows ? 'opencode.exe' : 'opencode';
  return context.join(home, '.opencode', 'bin', name);
}

/// Leftover npm `opencode-ai` (v1) shims must not win over the official v2 bin.
bool isStaleOpencodeNpmInstall(String path, {String? linkTarget}) {
  if (_looksLikeOpencodeAi(path) ||
      (linkTarget != null && _looksLikeOpencodeAi(linkTarget))) {
    return true;
  }
  final normalized = path.replaceAll('\\', '/');
  return normalized.endsWith('/.local/bin/opencode') ||
      normalized.endsWith('/.local/bin/opencode.exe');
}

bool _looksLikeOpencodeAi(String value) {
  final normalized = value.replaceAll('\\', '/');
  return normalized.contains('node_modules/opencode-ai') ||
      normalized.contains('/opencode-ai/bin/');
}

/// When the official v2 binary exists, skip npm v1 stubs and PATH leftovers.
String? preferOpencodeLaunchExecutable({
  required String userPath,
  required String? discoveredPath,
  required String? wellKnownPath,
  required bool Function(String path) isStaleInstall,
}) {
  final wellKnown = wellKnownPath?.trim() ?? '';
  if (wellKnown.isEmpty) return null;
  final user = userPath.trim();
  if (user.isNotEmpty && !isStaleInstall(user)) return user;
  final discovered = discoveredPath?.trim() ?? '';
  if (discovered.isNotEmpty && !isStaleInstall(discovered) && user.isEmpty) {
    return discovered;
  }
  return wellKnown;
}

/// Remote probe: official v2 dir first. Must match [DefaultRemoteCliLocator]
/// `sh -c` quoting used by `~/.local/bin` probes.
const opencodeOfficialRemoteBinProbe =
    'sh -c \'test -x "\$HOME/.opencode/bin/opencode" && '
    'printf "%s\\n" "\$HOME/.opencode/bin/opencode"\'';

/// Minimum OpenCode major version TeamPilot's generated `opencode.json` can run
/// on: it writes v2-only keys (`permissions`, `providers`, …) that v1 rejects.
const opencodeMinimumRemoteMajorVersion = 2;

/// Remote probe reading the version of the binary at [path]
/// (`<path> --version`).
String opencodeRemoteVersionProbeCommand(String path) {
  final quoted = path.replaceAll("'", r"'\''");
  return 'sh -c \'test -x "$quoted" && "$quoted" --version\'';
}

/// Major version from an OpenCode `--version` banner, or null when unreadable.
int? opencodeMajorVersionFromBanner(String banner) {
  final token = cliVersionToken(banner);
  if (token == null) return null;
  return int.tryParse(token.split('.').first);
}

String opencodePostInstallLocateScript({required String fallbackScript}) =>
    '''
if [ -x "\$HOME/.opencode/bin/opencode" ]; then
  printf '%s\\n' "\$HOME/.opencode/bin/opencode"
  exit 0
fi
if [ -x "\$HOME/.opencode/bin/opencode.exe" ]; then
  printf '%s\\n' "\$HOME/.opencode/bin/opencode.exe"
  exit 0
fi
$fallbackScript
''';

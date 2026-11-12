import 'package:path/path.dart' as p;

/// Official Grok Build binary path from https://x.ai/cli/install.sh.
String? grokOfficialExecutablePath({
  required String? homeDirectory,
  required bool isWindows,
}) {
  final home = homeDirectory?.trim() ?? '';
  if (home.isEmpty) return null;
  final context = isWindows ? p.windows : p.posix;
  final name = isWindows ? 'grok.exe' : 'grok';
  return context.join(home, '.grok', 'bin', name);
}

/// Remote probe: the official install dir first, then the standard PATH probe
/// performed by [DefaultRemoteCliLocator].
const grokOfficialRemoteBinProbe =
    'sh -c \'if [ -x "\$HOME/.grok/bin/grok" ]; then '
    'printf "%s\\n" "\$HOME/.grok/bin/grok"; '
    'elif [ -x "\$HOME/.grok/bin/grok.exe" ]; then '
    'printf "%s\\n" "\$HOME/.grok/bin/grok.exe"; '
    'else exit 1; fi\'';

/// Remote post-install locate: official install dir, then PATH/shell fallback.
String grokPostInstallLocateScript({required String fallbackScript}) =>
    '''
if [ -x "\$HOME/.grok/bin/grok" ]; then
  printf '%s\\n' "\$HOME/.grok/bin/grok"
  exit 0
fi
if [ -x "\$HOME/.grok/bin/grok.exe" ]; then
  printf '%s\\n' "\$HOME/.grok/bin/grok.exe"
  exit 0
fi
$fallbackScript
''';

/// Shared Termux / Android detection for remote SSH install & bootstrap scripts.
///
/// Detection is intentionally shell-side: TeamPilot only has an SSH session to
/// the work home, so Dart cannot rely on [Platform.isAndroid] for the remote.
abstract final class TermuxRemoteDetect {
  TermuxRemoteDetect._();

  /// Sets `is_termux` (0/1) and may export `PREFIX` for subsequent commands.
  static const ensurePrefixAndFlagShell = r'''
is_termux=0
if [ -n "${TERMUX_VERSION:-}" ]; then
  is_termux=1
fi
if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
  if [ -x "${PREFIX}/bin/pkg" ] || command -v pkg >/dev/null 2>&1; then
    is_termux=1
  fi
fi
if [ -d /data/data/com.termux/files/usr/bin ]; then
  export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
  if [ -x "$PREFIX/bin/pkg" ]; then
    is_termux=1
  fi
fi
''';

  /// One-shot probe: prints `TERMUX=1` or `TERMUX=0` on stdout.
  static String probeScript() =>
      '''
$ensurePrefixAndFlagShell
if [ "\$is_termux" -eq 1 ]; then
  printf 'TERMUX=1\\n'
else
  printf 'TERMUX=0\\n'
fi
''';

  static bool isTermuxFromProbeOutput(String stdout) =>
      stdout.contains('TERMUX=1');

  /// Prepend Termux `$PREFIX/bin` (and a well-known fallback) onto PATH.
  static const exportPrefixPathShell = r'''
export PATH="${PREFIX:+$PREFIX/bin:}$HOME/.local/bin:$PATH"
if [ -z "${PREFIX:-}" ] && [ -d /data/data/com.termux/files/usr/bin ]; then
  export PATH="/data/data/com.termux/files/usr/bin:$PATH"
fi
''';
}

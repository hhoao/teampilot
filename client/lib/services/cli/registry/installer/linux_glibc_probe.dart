/// Parses host glibc from `ldd --version` and classifies cursor-agent
/// dynamic-linker failures (needs glibc 2.28+).
abstract final class LinuxGlibcProbe {
  static const int cursorMinimumMajor = 2;
  static const int cursorMinimumMinor = 28;

  static String probeScript() => r'''
ver=$(ldd --version 2>&1 | awk 'NR==1 {print $NF}')
if [ -n "$ver" ]; then
  printf 'GLIBC=%s\n' "$ver"
else
  printf 'GLIBC=unknown\n'
fi
''';

  static ({int major, int minor})? parse(String stdout) {
    final match = RegExp(r'GLIBC=(\d+)\.(\d+)').firstMatch(stdout);
    if (match == null) return null;
    return (
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
    );
  }

  static bool isBelowCursorMinimum(String stdout) {
    final version = parse(stdout);
    if (version == null) return false;
    if (version.major != cursorMinimumMajor) {
      return version.major < cursorMinimumMajor;
    }
    return version.minor < cursorMinimumMinor;
  }

  static String formatVersion(String stdout) {
    final version = parse(stdout);
    if (version == null) return 'unknown';
    return '${version.major}.${version.minor}';
  }

  static String cursorUnsupportedMessage({
    required String hostId,
    required String detected,
  }) =>
      'Host $hostId has glibc $detected; cursor-agent requires glibc '
      '$cursorMinimumMajor.$cursorMinimumMinor or newer.';

  static bool looksLikeDynamicLinkerVersionError(String text) {
    final lower = text.toLowerCase();
    return (lower.contains('version `glibc_') &&
            lower.contains('not found')) ||
        (lower.contains('version `cxxabi_') && lower.contains('not found'));
  }

  static String launchFailureMessage() =>
      '[无法启动 cursor-agent：远端 glibc 低于 $cursorMinimumMajor.$cursorMinimumMinor。\n'
      '  cursor-agent 需要 glibc $cursorMinimumMajor.$cursorMinimumMinor 或更高版本'
      '（例如 Ubuntu 18.04+ / RHEL 8+）。]';
}

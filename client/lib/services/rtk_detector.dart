import 'dart:io';

/// Result of probing the host for RTK CLI dependencies.
class RtkProbeResult {
  const RtkProbeResult({
    required this.found,
    this.executablePath,
    this.version,
    this.jqFound = false,
  });

  final bool found;
  final String? executablePath;
  final String? version;
  final bool jqFound;

  bool get isReady =>
      found &&
      jqFound &&
      (version == null || const RtkDetector().isVersionSupported(version!));
}

typedef RtkProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

/// Locates `rtk` and `jq` on PATH for hook provisioning.
class RtkDetector {
  const RtkDetector({RtkProcessRunner? processRunner})
    : _processRunner = processRunner ?? Process.run;

  final RtkProcessRunner _processRunner;

  static final _versionPattern = RegExp(r'(\d+)\.(\d+)\.(\d+)');

  Future<RtkProbeResult> probe({Map<String, String>? environment}) async {
    final locator = Platform.isWindows ? 'where' : 'which';
    final rtkPath = await _resolveExecutable(locator, 'rtk', environment);
    if (rtkPath == null) {
      return const RtkProbeResult(found: false);
    }

    final jqFound = await _resolveExecutable(locator, 'jq', environment) != null;

    String? version;
    try {
      final result = await _processRunner(
        rtkPath,
        const ['--version'],
        environment: environment,
      );
      if (result.exitCode == 0) {
        version = _parseVersion(result.stdout.toString());
      }
    } on Object {
      version = null;
    }

    return RtkProbeResult(
      found: true,
      executablePath: rtkPath,
      version: version,
      jqFound: jqFound,
    );
  }

  bool isVersionSupported(String version) {
    final match = _versionPattern.firstMatch(version.trim());
    if (match == null) return false;
    final major = int.tryParse(match.group(1) ?? '') ?? 0;
    final minor = int.tryParse(match.group(2) ?? '') ?? 0;
    if (major > 0) return true;
    return minor >= 23;
  }

  String? _parseVersion(String raw) {
    final match = _versionPattern.firstMatch(raw);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }

  Future<String?> _resolveExecutable(
    String locator,
    String name,
    Map<String, String>? environment,
  ) async {
    try {
      final result = await _processRunner(
        locator,
        [name],
        environment: environment,
      );
      if (result.exitCode != 0) return null;
      final line = result.stdout.toString().trim().split(RegExp(r'\r?\n')).first;
      return line.isEmpty ? null : line;
    } on Object {
      return null;
    }
  }
}

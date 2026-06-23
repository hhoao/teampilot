import 'dart:io';

import '../../models/extension_manifest.dart';
import '../host/host_executable_locator.dart';
import '../host/host_execution_environment.dart';
import '../storage/runtime_context.dart';
import '../storage/app_storage.dart';
import 'extension_probe.dart';

typedef ExtensionProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// Probes the host for an extension's tool + companion binaries, parameterized
/// by an [ExtensionDetectSpec]. Generalizes the former `RtkDetector`.
class ExtensionDetector {
  ExtensionDetector({ExtensionProcessRunner? processRunner, bool? probeHost})
      : _processRunner = processRunner ?? Process.run,
        _probeHost = probeHost ??
            (processRunner != null ||
                Platform.environment['FLUTTER_TEST'] != 'true');

  final ExtensionProcessRunner _processRunner;
  final bool _probeHost;

  static final _versionPattern = RegExp(r'(\d+)\.(\d+)\.(\d+)');

  Future<ExtensionProbe> probe(
    ExtensionDetectSpec spec, {
    Map<String, String>? environment,
  }) async {
    // Widget tests use fake async; default [Process.run] leaves pending timers.
    if (!_probeHost) return const ExtensionProbe(found: false);

    final locator = _pathLocator();
    final exePath = await _resolveExecutable(
      locator.whichCommand,
      spec.executable,
      environment,
    );
    if (exePath == null) return const ExtensionProbe(found: false);

    final missing = <String>[];
    for (final dep in spec.requires) {
      final depPath =
          await _resolveExecutable(locator.whichCommand, dep, environment);
      if (depPath == null) missing.add(dep);
    }

    String? version;
    try {
      final result = await _processRunner(
        exePath,
        spec.versionArgs,
        environment: environment,
      );
      if (result.exitCode == 0) {
        version = _parseVersion(result.stdout.toString());
      }
    } on Object {
      version = null;
    }

    final satisfies = spec.minVersion == null ||
        version == null ||
        _meetsMinVersion(version, spec.minVersion!);

    return ExtensionProbe(
      found: true,
      executablePath: exePath,
      version: version,
      satisfiesMinVersion: satisfies,
      missingRequirements: missing,
    );
  }

  String? _parseVersion(String raw) {
    final match = _versionPattern.firstMatch(raw);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }

  bool _meetsMinVersion(String version, String minVersion) {
    final v = _versionTriple(version);
    final min = _versionTriple(minVersion);
    if (v == null || min == null) return true;
    for (var i = 0; i < 3; i++) {
      if (v[i] != min[i]) return v[i] > min[i];
    }
    return true;
  }

  List<int>? _versionTriple(String raw) {
    final match = _versionPattern.firstMatch(raw.trim());
    if (match == null) return null;
    return [
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
    ];
  }

  HostExecutableLocator _pathLocator() {
    final env = AppStorage.isInstalled
        ? HostExecutionEnvironment.fromStorage(AppStorage.context)
        : HostExecutionEnvironment.resolve();
    return HostExecutableLocator(env);
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
      final line =
          result.stdout.toString().trim().split(RegExp(r'\r?\n')).first;
      return line.isEmpty ? null : line;
    } on Object {
      return null;
    }
  }
}

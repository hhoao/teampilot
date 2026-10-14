import 'dart:convert';

import 'cli_tool_locator.dart';

class CliVersionProbe {
  CliVersionProbe({ProcessRunner runner = cliToolDefaultProcessRun})
    : _runner = runner;

  final ProcessRunner _runner;

  Future<String?> installed(String absolutePath) async {
    if (absolutePath.isEmpty) return null;
    if (!absolutePath.contains('/') && !absolutePath.contains(r'\')) {
      return null;
    }
    try {
      final result = await _runner(absolutePath, const ['--version']);
      if (result.exitCode != 0) return null;
      return _firstTrimmedNonEmptyLine(result.stdout);
    } on Object {
      return null;
    }
  }

  Future<String?> latestNpm(String npmPackage) async {
    try {
      final result = await _runner('npm', ['view', npmPackage, 'version']);
      if (result.exitCode != 0) return null;
      return _firstTrimmedNonEmptyLine(result.stdout);
    } on Object {
      return null;
    }
  }

  String? _firstTrimmedNonEmptyLine(Object? stdout) {
    final text = stdout?.toString() ?? '';
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

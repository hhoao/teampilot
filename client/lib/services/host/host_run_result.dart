import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../ssh/ssh_run_result.dart';

/// Unified result for [HostOneShotRunner] (local [ProcessResult] or SSH exec).
@immutable
class HostRunResult {
  const HostRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;

  factory HostRunResult.fromProcess(ProcessResult result) {
    return HostRunResult(
      exitCode: result.exitCode,
      stdout: _asString(result.stdout),
      stderr: _asString(result.stderr),
    );
  }

  factory HostRunResult.fromSsh(SSHRunResult result) {
    return HostRunResult(
      exitCode: result.exitCode ?? (sshRunSucceeded(result) ? 0 : 1),
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  }

  static String _asString(Object? value) {
    if (value is String) return value;
    if (value is List<int>) {
      return utf8.decode(value, allowMalformed: true);
    }
    return value?.toString() ?? '';
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/logging/logger.dart';
import '../host/host_one_shot_runner.dart';
import '../host/host_one_shot_runner_for_context.dart';
import '../host/host_process_starter.dart';
import '../host/host_process_starter_for_context.dart';
import '../storage/app_storage.dart';
import 'credential_login_url_detector.dart';

typedef CredentialOpenUrl = Future<void> Function(Uri uri);

/// Runs provider credential login/logout CLIs on the home runtime plane.
class ProviderCredentialHostRunner {
  ProviderCredentialHostRunner({
    required HostOneShotRunner Function() oneShot,
    required HostProcessStarter Function() streaming,
    CredentialOpenUrl? openUrl,
    CredentialLoginUrlDetector urlDetector = const CredentialLoginUrlDetector(),
  }) : _oneShot = oneShot,
       _streaming = streaming,
       _openUrl = openUrl,
       _urlDetector = urlDetector;

  static const _maxTailBytes = 2048;

  final HostOneShotRunner Function() _oneShot;
  final HostProcessStarter Function() _streaming;
  final CredentialOpenUrl? _openUrl;
  final CredentialLoginUrlDetector _urlDetector;

  /// Logout / revoke: one-shot on home host.
  Future<HostRunResult> run(HostRunRequest request) async {
    try {
      return await _oneShot().run(request);
    } on ProcessException {
      rethrow;
    } on Object catch (error) {
      throw ProcessException(
        request.executable,
        request.arguments,
        error.toString(),
      );
    }
  }

  /// Login: stream output, open first HTTPS URL(s) on device, return final result.
  Future<HostRunResult> runLogin(HostRunRequest request) async {
    final handle = await _startStreaming(request);

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var tail = '';
    final openedUris = <String>{};
    var chain = Future<void>.value();

    void scheduleChunk(List<int> bytes, {required bool isStderr}) {
      chain = chain.then((_) async {
        final chunk = utf8.decode(bytes, allowMalformed: true);
        if (isStderr) {
          stderrBuffer.write(chunk);
        } else {
          stdoutBuffer.write(chunk);
        }
        await _scanAndOpenUrls(tail + chunk, openedUris);
        tail = _rollingTail(tail + chunk);
      });
    }

    final stdoutDone = handle.stdout.forEach(
      (chunk) => scheduleChunk(chunk, isStderr: false),
    );
    final stderrDone = handle.stderr.forEach(
      (chunk) => scheduleChunk(chunk, isStderr: true),
    );

    await Future.wait<void>([stdoutDone, stderrDone]);
    await chain;
    await _scanAndOpenUrls(
      '${stdoutBuffer}${stderrBuffer}',
      openedUris,
      allowTrailing: true,
    );

    final exitCode = await handle.exitCode;
    return HostRunResult(
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }

  /// Production/service default — lazy [AppStorage.context] binding.
  static ProviderCredentialHostRunner forAppStorage({CredentialOpenUrl? openUrl}) {
    return ProviderCredentialHostRunner(
      oneShot: () => hostOneShotRunnerForContext(AppStorage.context),
      streaming: () => hostProcessStarterForContext(AppStorage.context),
      openUrl: openUrl,
    );
  }

  Future<dynamic> _startStreaming(HostRunRequest request) async {
    try {
      return await _streaming().start(request);
    } on ProcessException {
      rethrow;
    } on Object catch (error) {
      throw ProcessException(
        request.executable,
        request.arguments,
        error.toString(),
      );
    }
  }

  Future<void> _scanAndOpenUrls(
    String text,
    Set<String> openedUris, {
    bool allowTrailing = false,
  }) async {
    final openUrl = _openUrl;
    if (openUrl == null) return;

    for (final uri in _withoutUriPrefixes(_urlDetector.extractAll(text))) {
      final key = uri.toString();
      if (openedUris.contains(key)) continue;

      final index = text.lastIndexOf(key);
      if (!allowTrailing && index >= 0 && _mightBeIncomplete(text, index, key)) {
        continue;
      }

      openedUris.add(key);
      try {
        await openUrl(uri);
      } on Object catch (error, stackTrace) {
        AppLogger.instance.w(
          'Failed to open credential login URL: $uri',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  static bool _mightBeIncomplete(String text, int index, String key) {
    final remainder = text.substring(index + key.length);
    if (remainder.isEmpty) return true;
    return RegExp(r'^[)\],.;:]+$').hasMatch(remainder);
  }

  static List<Uri> _withoutUriPrefixes(List<Uri> uris) {
    return [
      for (final uri in uris)
        if (!uris.any(
          (other) =>
              other != uri &&
              other.toString().startsWith(uri.toString()) &&
              other.toString().length > uri.toString().length,
        ))
          uri,
    ];
  }

  static String _rollingTail(String combined) {
    final encoded = utf8.encode(combined);
    if (encoded.length <= _maxTailBytes) return combined;
    final suffix = encoded.sublist(encoded.length - _maxTailBytes);
    return utf8.decode(suffix, allowMalformed: true);
  }
}

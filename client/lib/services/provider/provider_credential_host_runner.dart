import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/logging/logger.dart';
import '../host/host_one_shot_runner.dart';
import '../host/host_one_shot_runner_for_context.dart';
import '../host/host_process_starter.dart';
import '../host/host_process_starter_for_context.dart';
import '../host/process_run_handle.dart';
import '../storage/app_storage.dart';
import 'credential_login_progress.dart';
import 'credential_login_url_detector.dart';

export 'credential_login_progress.dart';

typedef CredentialOpenUrl = Future<void> Function(Uri uri);
typedef CredentialLoginHint = void Function(CredentialLoginProgress progress);

/// Runs provider credential login/logout CLIs on the home runtime plane.
class ProviderCredentialHostRunner {
  ProviderCredentialHostRunner({
    required HostOneShotRunner Function() oneShot,
    required HostProcessStarter Function() streaming,
    CredentialOpenUrl? openUrl,
    CredentialLoginHint? onLoginHint,
    CredentialLoginUrlDetector urlDetector = const CredentialLoginUrlDetector(),
  }) : _oneShot = oneShot,
       _streaming = streaming,
       _openUrl = openUrl,
       _onLoginHint = onLoginHint,
       _urlDetector = urlDetector;

  static const _maxTailBytes = 2048;

  final HostOneShotRunner Function() _oneShot;
  final HostProcessStarter Function() _streaming;
  final CredentialOpenUrl? _openUrl;
  final CredentialLoginHint? _onLoginHint;
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
    final handle = await _startStreaming(
      HostRunRequest(
        executable: request.executable,
        arguments: request.arguments,
        workingDirectory: request.workingDirectory,
        environment: request.environment,
        includeParentEnvironment: request.includeParentEnvironment,
        allocateTty: true,
      ),
    );

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var tail = '';
    final openedUris = <String>{};
    final announcedDeviceCodes = <String>{};
    var chain = Future<void>.value();

    void scheduleChunk(List<int> bytes, {required bool isStderr}) {
      chain = chain.then((_) async {
        final chunk = utf8.decode(bytes, allowMalformed: true);
        if (isStderr) {
          stderrBuffer.write(chunk);
        } else {
          stdoutBuffer.write(chunk);
        }
        await _scanAndOpenUrls(
          tail + chunk,
          openedUris,
          announcedDeviceCodes: announcedDeviceCodes,
        );
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
      '$stdoutBuffer$stderrBuffer',
      openedUris,
      allowTrailing: true,
      announcedDeviceCodes: announcedDeviceCodes,
    );

    final exitCode = await handle.exitCode;
    return HostRunResult(
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }

  /// Production/service default — lazy [AppStorage.context] binding.
  static ProviderCredentialHostRunner forAppStorage({
    CredentialOpenUrl? openUrl,
    CredentialLoginHint? onLoginHint,
  }) {
    return ProviderCredentialHostRunner(
      oneShot: () => hostOneShotRunnerForContext(AppStorage.context),
      streaming: () => hostProcessStarterForContext(AppStorage.context),
      openUrl: openUrl,
      onLoginHint: onLoginHint,
    );
  }

  Future<ProcessRunHandle> _startStreaming(HostRunRequest request) async {
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
    Set<String>? announcedDeviceCodes,
  }) async {
    final codes = announcedDeviceCodes;
    if (codes != null) {
      for (final code in _urlDetector.extractDeviceCodes(text)) {
        if (!codes.add(code)) continue;
        _announceDeviceCode(code, text);
      }
    }

    final openUrl = _openUrl;
    if (openUrl == null) return;

    for (final uri in _withoutUriPrefixes(_urlDetector.extractAll(text))) {
      final key = uri.toString();
      if (openedUris.contains(key)) continue;

      final cleaned = CredentialLoginUrlDetector.stripAnsi(text);
      final index = cleaned.lastIndexOf(key);
      if (!allowTrailing &&
          index >= 0 &&
          _mightBeIncomplete(cleaned, index, key)) {
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

  void _announceDeviceCode(String code, String text) {
    AppLogger.instance.i('Credential login device code: $code');
    final uris = _withoutUriPrefixes(_urlDetector.extractAll(text));
    _onLoginHint?.call(
      CredentialLoginProgress(
        deviceCode: code,
        verificationUri: uris.isEmpty ? null : uris.first,
      ),
    );
  }

  static bool _mightBeIncomplete(String text, int index, String key) {
    final remainder = text.substring(index + key.length);
    if (RegExp(r'^[)\],.;:]+$').hasMatch(remainder)) return true;
    if (remainder.isNotEmpty) return false;

    // Empty remainder while the process is still running (common for OAuth):
    // open if the URI already looks finished; keep waiting only for truncated
    // hosts like `https://auth` mid-chunk.
    final uri = Uri.tryParse(key);
    if (uri == null) return true;
    if (!uri.host.contains('.')) return true;
    if (uri.hasQuery || uri.hasFragment) return false;
    return uri.path.isEmpty || uri.path == '/';
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

@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/cli/antigravity/antigravity_tool.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';

/// End-to-end local smoke for Antigravity's ACP adapter (`agy_acp_server`).
///
/// Spawns the real adapter through the app's production seams
/// (`productionAcpSpawner` + `AcpSessionRuntime`) and drives one prompt turn.
/// Requires the adapter (installed via the app toolchain or on PATH) and a
/// logged-in Antigravity account; skipped otherwise.
///
/// ```bash
/// dart run tool/run_tests.dart --tags integration \
///   test/integration/antigravity_acp_local_smoke_test.dart
/// ```
void main() {
  test('antigravity ACP completes initialize / session/new / prompt', () async {
    final adapter = await _locateAdapter();
    if (adapter == null) {
      markTestSkipped('agy_acp_server not installed (toolchain or PATH)');
      return;
    }

    final temp = Directory.systemTemp.createTempSync('antigravity-acp-');
    final registry = CliToolRegistry()..register(const AntigravityCliTool());
    final logger = AcpFrameLogger(mirrorToLog: false);
    final runtime = AcpSessionRuntime(
      spawner: productionAcpSpawner(
        registry: registry,
        tool: CliTool.antigravity,
        workingDirectory: temp.path,
        logger: logger,
        handshakeTimeout: const Duration(seconds: 120),
      ),
      logger: logger,
      launchPlanFor: acpLaunchPlanResolver(
        registry,
        discoveredAdapterPath: (_) => adapter,
      ),
    );

    try {
      final apiKey = Platform.environment['GEMINI_API_KEY']?.trim() ?? '';
      try {
        await runtime.start(
          tool: CliTool.antigravity,
          executable: adapter,
          sessionToolDir: temp.path,
          workingDirectory: temp.path,
          baseEnv: <String, String>{
            'PATH': Platform.environment['PATH'] ?? '',
            if (apiKey.isNotEmpty) 'GEMINI_API_KEY': apiKey,
          },
        );
      } on Object catch (error) {
        if (_isAuthRequired(error)) {
          markTestSkipped('agy_acp_server is not authenticated: $error');
          return;
        }
        rethrow;
      }
      expect(runtime.isStarted, isTrue);

      final reply = StringBuffer();
      final updates = runtime.updates.listen((update) {
        if (update is AcpMessageChunk && update.role == AcpRole.assistant) {
          reply.write(update.content);
        }
      });
      try {
        await runtime.prompt('Reply with exactly: ok');
      } on Object catch (error) {
        if (_isAuthRequired(error)) {
          markTestSkipped('agy_acp_server is not authenticated: $error');
          return;
        }
        rethrow;
      } finally {
        await updates.cancel();
      }

      expect(reply.toString().toLowerCase(), contains('ok'));
    } finally {
      await runtime.close();
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort temp cleanup.
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Resolves the adapter from the installer's toolchain directory (the same
/// probe the readiness UI uses) and falls back to `PATH`.
Future<String?> _locateAdapter() async {
  final fromPath =
      await _which('agy_acp_server.par') ??
      await _which('agy_acp_server') ??
      await _which('agy_acp_server.exe');
  if (fromPath != null) return fromPath;

  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (home.isEmpty) return null;
  final roots = <String>[
    AppPaths.defaultTeampilotAppDataDirForHome(home),
    if (Platform.environment['TEAMPILOT_ROOT'] case final root?
        when root.trim().isNotEmpty)
      root,
  ];
  for (final root in roots) {
    final installer = AntigravityAcpAdapterInstaller(
      storage: HomeStorage.forTesting(
        filesystem: LocalFilesystem(),
        paths: AppPaths(root),
        home: home,
        cwd: Directory.systemTemp.path,
      ),
    );
    final installed = await installer.resolveInstalledPath();
    if (installed != null) return installed;
  }
  return null;
}

bool _isAuthRequired(Object error) {
  if (error is AcpAuthenticateException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('authentication required') ||
      text.contains('auth required') ||
      text.contains('not logged in') ||
      text.contains('login required') ||
      text.contains('code: -32000') ||
      text.contains('credential');
}

Future<String?> _which(String name) async {
  try {
    final result = await Process.run('which', [name]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String? ?? '').trim();
    return path.isEmpty ? null : path;
  } on ProcessException {
    return null;
  }
}

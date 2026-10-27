@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/cli/codebuddy/codebuddy_tool.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

/// End-to-end local smoke for the CodeBuddy CLI over ACP.
///
/// Spawns the real `codebuddy --acp` through the app's production seams
/// (`productionAcpSpawner` + `AcpSessionRuntime`) and drives one prompt turn.
/// Requires a logged-in CLI on PATH; skipped otherwise.
///
/// ```bash
/// dart run tool/run_tests.dart --tags integration \
///   test/integration/codebuddy_acp_local_smoke_test.dart
/// ```
void main() {
  test('codebuddy --acp completes initialize / session/new / prompt', () async {
    final executable = await _which('codebuddy');
    if (executable == null) {
      // ignore: avoid_print
      print('[codebuddy-acp] skipped: `codebuddy` is not on PATH');
      return;
    }

    final temp = Directory.systemTemp.createTempSync('codebuddy-acp-');
    final registry = CliToolRegistry()..register(const CodebuddyCliTool());
    final logger = AcpFrameLogger(mirrorToLog: false);
    final runtime = AcpSessionRuntime(
      spawner: productionAcpSpawner(
        registry: registry,
        tool: CliTool.codebuddy,
        workingDirectory: temp.path,
        logger: logger,
        handshakeTimeout: const Duration(seconds: 60),
      ),
      logger: logger,
      launchPlanFor: acpLaunchPlanResolver(registry),
    );

    try {
      await runtime.start(
        tool: CliTool.codebuddy,
        executable: executable,
        sessionToolDir: temp.path,
        workingDirectory: temp.path,
        baseEnv: {'PATH': Platform.environment['PATH'] ?? ''},
      );
      expect(runtime.isStarted, isTrue);

      final reply = StringBuffer();
      final updates = runtime.updates.listen((update) {
        if (update is AcpMessageChunk && update.role == AcpRole.assistant) {
          reply.write(update.content);
        }
      });
      await runtime.prompt('Reply with exactly: pong');
      await updates.cancel();

      expect(reply.toString().toLowerCase(), contains('pong'));
    } finally {
      await runtime.close();
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort temp cleanup.
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
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

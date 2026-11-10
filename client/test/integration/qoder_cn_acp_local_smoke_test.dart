@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';
import 'package:teampilot/services/cli/qoder/qoder_tool.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

/// End-to-end local smoke for the Qoder CN CLI over ACP.
///
/// Spawns the real `qoderclicn --acp` through the production seams and drives
/// one prompt turn. `QODER_CONFIG_DIR` points at a temp dir seeded from
/// `QODER_CN_AUTH_DIR` (must contain `user` and `machine_id`). The test skips
/// when the binary or the auth source is missing.
///
/// ```bash
/// QODER_CN_AUTH_DIR=/path/to/.auth \
///   dart run tool/run_tests.dart --tags integration \
///   test/integration/qoder_cn_acp_local_smoke_test.dart
/// ```
void main() {
  test('qoderclicn --acp completes initialize / session/new / prompt', () async {
    final executable = await _which('qoderclicn');
    final auth = Platform.environment['QODER_CN_AUTH_DIR'] ?? '';
    final hasAuthPair =
        auth.isNotEmpty &&
        File(p.join(auth, 'user')).existsSync() &&
        File(p.join(auth, 'machine_id')).existsSync();
    if (executable == null || !hasAuthPair) {
      markTestSkipped(
        '[qoder-cn-acp] skipped: qoderclicn or QODER_CN_AUTH_DIR '
        '({user,machine_id}) is missing',
      );
      return;
    }

    final temp = Directory.systemTemp.createTempSync('qoder-cn-acp-');
    Directory(p.join(temp.path, '.auth')).createSync(recursive: true);
    for (final name in const ['user', 'machine_id']) {
      File(p.join(auth, name)).copySync(p.join(temp.path, '.auth', name));
    }

    final registry = CliToolRegistry()
      ..register(QoderCliTool(flavor: QoderFlavor.cn));
    final logger = AcpFrameLogger(mirrorToLog: false);
    final runtime = AcpSessionRuntime(
      spawner: productionAcpSpawner(
        registry: registry,
        tool: CliTool.qoderCn,
        workingDirectory: temp.path,
        logger: logger,
        handshakeTimeout: const Duration(seconds: 60),
      ),
      logger: logger,
      launchPlanFor: acpLaunchPlanResolver(registry),
    );

    try {
      await runtime.start(
        tool: CliTool.qoderCn,
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

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/cursor/capabilities/session_lifecycle.dart';
import 'package:teampilot/services/launch/work_plane_script_runner.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  test('only cursor session capability performs post-flush work', () {
    final registry = CliToolRegistry.builtIn();
    final cursorCap = registry.capability<CliSessionCapability>(CliTool.cursor);
    expect(cursorCap, isA<CursorSessionLifecycleCapability>());
    for (final cli in CliTool.values) {
      if (cli == CliTool.cursor) continue;
      expect(
        registry.capability<CliSessionCapability>(cli),
        isNot(isA<CursorSessionLifecycleCapability>()),
        reason: cli.value,
      );
    }
  });

  group('CursorSessionLifecycleCapability.afterManifestFlush', () {
    late InMemoryFilesystem fs;
    late CursorSessionLifecycleCapability capability;

    setUp(() {
      fs = InMemoryFilesystem();
      capability = const CursorSessionLifecycleCapability();
    });

    test('local path mirrors real home into member HOME', () async {
      const realHome = '/home/alice';
      const memberHome = '/tmp/member-home';
      await fs.ensureDir('$realHome/.cargo');
      await fs.ensureDir('$memberHome/${CursorHomeLayout.cursorDirName}');

      await capability.afterManifestFlush(
        PostManifestFlushContext(
          workFs: fs,
          workHome: realHome,
          environment: const {'HOME': memberHome},
        ),
      );

      expect((await fs.stat('$memberHome/.cargo')).isSymlink, isTrue);
      expect(
        await fs.readSymlinkTarget('$memberHome/.cargo'),
        '$realHome/.cargo',
      );
    });

    test('remote path runs mirror script via WorkPlaneScriptRunner', () async {
      String? ran;
      final runner = _RecordingRunner((script) {
        ran = script;
      });

      await capability.afterManifestFlush(
        PostManifestFlushContext(
          workFs: fs,
          workHome: '/home/alice',
          environment: const {'HOME': '/tmp/member-home'},
          remoteRunner: runner,
        ),
      );

      expect(ran, isNotNull);
      expect(ran, contains("real_home='/home/alice'"));
      expect(ran, contains("member_home='/tmp/member-home'"));
      expect(ran, contains('link_passthrough'));
    });

    test('no-ops when HOME matches work home', () async {
      var ran = false;
      await capability.afterManifestFlush(
        PostManifestFlushContext(
          workFs: fs,
          workHome: '/home/alice',
          environment: const {'HOME': '/home/alice'},
          remoteRunner: _RecordingRunner((_) {
            ran = true;
          }),
        ),
      );
      expect(ran, isFalse);
    });
  });
}

final class _RecordingRunner implements WorkPlaneScriptRunner {
  _RecordingRunner(this.onRun);

  final void Function(String script) onRun;

  @override
  Future<void> runScript(
    String script, {
    required String operation,
    Duration? timeout,
  }) async {
    onRun(script);
  }
}

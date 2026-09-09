import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';

/// Records every [HostRunRequest] so tests can assert on the PATH entries the
/// service prepends for native CLI plugin commands.
final class _RecordingRunner implements HostOneShotRunner {
  final calls = <HostRunRequest>[];

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    calls.add(request);
    return const HostRunResult(exitCode: 0, stdout: '{}', stderr: '');
  }
}

void main() {
  Future<(_RecordingRunner, List<String>)> provisionWith({
    String? Function()? preferredNodePath,
  }) async {
    final fs = InMemoryFilesystem();
    final runner = _RecordingRunner();
    final service = ConfigProfileService(
      basePath: '/tp',
      home: '/home/u',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      hostOneShotRunner: runner,
      preferredNodePath: preferredNodePath,
    );
    await service.provisionNativePlugins(
      workspaceId: 'ws',
      sessionId: 'sess',
      runtimeBundle: const ConfigBundle(),
      cli: CliTool.codex,
    );
    return (runner, [for (final call in runner.calls) ...call.pathPrepend]);
  }

  test(
    'provisionNativePlugins prepends the resolved node bin directory',
    () async {
      final (_, paths) = await provisionWith(
        preferredNodePath: () => '/home/u/.nvm/versions/node/v22.18.0/bin/node',
      );

      expect(
        paths,
        contains('/home/u/.nvm/versions/node/v22.18.0/bin'),
        reason:
            'codex resolves via ~/.local/bin but its #!/usr/bin/env node '
            'shebang needs the discovered node directory on PATH',
      );
    },
  );

  test('empty resolved node path adds no PATH entries', () async {
    final (runner, _) = await provisionWith(preferredNodePath: () => '');

    expect(
      runner.calls.map((call) => call.pathPrepend),
      everyElement(hasLength(2)),
      reason: 'only the toolchain + ~/.local/bin entries remain',
    );
  });

  test('bare "node" fallback adds no PATH entries', () async {
    final (runner, _) = await provisionWith(preferredNodePath: () => 'node');

    expect(
      runner.calls.map((call) => call.pathPrepend),
      everyElement(hasLength(2)),
      reason: 'a bare command name has no directory to prepend',
    );
  });

  test('without a resolver the PATH entries stay unchanged', () async {
    final (runner, paths) = await provisionWith();

    expect(runner.calls, isNotEmpty);
    expect(
      runner.calls.map((call) => call.pathPrepend),
      everyElement(
        containsAllInOrder([
          '/tp/toolchain/node/current/bin',
          '/home/u/.local/bin',
        ]),
      ),
    );
    expect(paths.toSet(), {
      '/tp/toolchain/node/current/bin',
      '/home/u/.local/bin',
    });
  });
}

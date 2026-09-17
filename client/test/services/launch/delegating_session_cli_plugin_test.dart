import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/services/launch/delegating_session_cli_plugin.dart';
import 'package:teampilot/services/launch/session_init_request_mapper.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('SessionScheduler.init applies delegated contribute writes', () async {
    final posix = p.Context(style: p.Style.posix);
    final home = InMemoryFilesystem(pathContext: posix);
    final work = InMemoryFilesystem(pathContext: posix);
    await work.ensureDir('/w');

    final plugin = DelegatingSessionCliPlugin(
      toolId: 'cursor',
      onContribute:
          ({
            required request,
            required layout,
            required homeFs,
            required workFs,
            required manifest,
          }) async {
            manifest.writeFile('${request.workRoot}/hello.txt', 'hi');
          },
      onSessionConfigDir: (layout, request) => layout.sessionRuntimeToolDir(
        request.workspaceId,
        request.sessionId,
        request.cli,
        memberId: request.memberId,
      ),
      onAfterApply:
          ({required workFs, required layout, required environment}) async {},
      onBuildSpawn:
          ({required request, required layout, required environment}) {
            return SessionSpawnSpec(
              executable: request.cliExecutablePath,
              argv: const [],
              env: environment,
              cwd: request.workingDirectory,
            );
          },
    );

    final result = await const SessionScheduler().init(
      request: sessionInitRequestFromConnect(
        workspaceId: 'w',
        sessionId: 's',
        memberId: 's',
        cli: 'cursor',
        cliExecutablePath: '/bin/cursor-agent',
        homeRoot: '/h',
        workRoot: '/w',
        securityPolicy: LaunchSecurityPolicy.fullAccess,
      ),
      homeFs: home,
      workFs: work,
      plugin: plugin,
    );

    expect(await work.readString('/w/hello.txt'), 'hi');
    expect(result.spawn.executable, '/bin/cursor-agent');
    expect(result.spawn.argv, isEmpty);
  });
}

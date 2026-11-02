import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/qoder/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('seeds the session config dir from the provider auth store', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: storage,
    );
    final capability = QoderProviderCapability(storage: storage);

    await fs.ensureDir('/tp/providers/qoder/work');
    await fs.atomicWrite('/tp/providers/qoder/work/user', 'USER');
    await fs.atomicWrite('/tp/providers/qoder/work/machine_id', 'MID');

    const member = TeamMemberConfig(id: 'm1', name: 'Member', provider: 'work');
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );

    final contribution = await capability.materializeSessionHome(
      sessionHomeContextFromLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
          catalog: service,
        ),
        CliTool.qoder,
      ),
    );

    final configDir =
        contribution.environment[QoderProviderCapability.configDirEnvKey]!;
    expect(await fs.readString(p.posix.join(configDir, '.auth', 'user')), 'USER');
    expect(
      await fs.readString(p.posix.join(configDir, '.auth', 'machine_id')),
      'MID',
    );
  });
}

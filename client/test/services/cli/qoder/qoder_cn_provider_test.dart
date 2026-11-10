import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/qoder/capabilities/provider.dart';
import 'package:teampilot/services/cli/qoder/provider_presets.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('CN capability exposes only the qoder-cn preset', () {
    const cap = QoderProviderCapability(flavor: QoderFlavor.cn);

    expect(cap.catalogCli, CliTool.qoderCn);
    expect(cap.defaultOfficialProviderId, 'qoder-cn');
    expect(cap.loginExecutableName, 'qoderclicn');
    expect(cap.presets, hasLength(1));

    final preset = cap.presets.single;
    expect(preset.id, 'qoder-cn');
    expect(preset.template.cli, CliTool.qoderCn);
    expect(preset.template.websiteUrl, 'https://qoder.com.cn');
    expect(QoderProviderPresets.byId('qoder-cn')!.id, 'qoder-cn');
  });

  test('CN materializes an isolated qoder-cn session home', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: storage,
    );
    // The auth store is read from the capability's injected storage (the
    // registry does the same); without it nothing is seeded into `.auth`.
    final capability = QoderProviderCapability(
      storage: storage,
      flavor: QoderFlavor.cn,
    );

    await fs.ensureDir('/tp/providers/qoder-cn/work');
    await fs.atomicWrite('/tp/providers/qoder-cn/work/user', 'CNUSER');
    await fs.atomicWrite('/tp/providers/qoder-cn/work/machine_id', 'CNMID');
    // The global provider store and the machine login must be ignored.
    await fs.ensureDir('/tp/providers/qoder/work');
    await fs.atomicWrite('/tp/providers/qoder/work/user', 'GLOBAL');
    await fs.atomicWrite('/tp/providers/qoder/work/machine_id', 'GLOBALMID');
    await fs.ensureDir('/home/test/.qoder/.auth');
    await fs.atomicWrite('/home/test/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/test/.qoder/.auth/machine_id', 'MACHID');

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
        CliTool.qoderCn,
      ),
    );

    final configDir =
        contribution.environment[QoderProviderCapability.configDirEnvKey]!;
    expect(configDir, contains('/runtime/qoder-cn'));
    expect(
      await fs.readString(p.posix.join(configDir, '.auth', 'user')),
      'CNUSER',
    );
    expect(
      await fs.readString(p.posix.join(configDir, '.auth', 'machine_id')),
      'CNMID',
    );
  });
}

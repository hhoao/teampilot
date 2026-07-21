import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test(
    'contributeLaunch sets OPENCODE_DB to session opencode.db',
    () async {
      final base = await Directory.systemTemp.createTemp('opencode_db_env_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = OpencodeConfigProfileCapability();
      const member = TeamMemberConfig(
        id: 'solo',
        name: 'Solo',
        model: 'big-pickle',
        provider: 'opencode',
      );

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: '',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: '',
      );

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: '',
          sessionId: scope.sessionId,
          scope: scope,
          team: null,
          member: member,
          members: const [member],
          paths: service,
          catalog: service,
        ),
      );

      final opencodeDir = service.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        'opencode',
      );

      // anomalyco/opencode: Flag.OPENCODE_DB absolute path overrides Database.Path
      // (packages/core/src/database/database.ts). There is no OPENCODE_DATA_DIR.
      expect(
        contribution.environment[OpencodeConfigProfileCapability.configDirEnv],
        opencodeDir,
      );
      expect(
        contribution.environment[OpencodeConfigProfileCapability.dbPathEnv],
        p.join(opencodeDir, 'opencode.db'),
      );
      expect(
        contribution.environment.containsKey('OPENCODE_DATA_DIR'),
        isFalse,
      );
      expect(contribution.environment.containsKey('XDG_DATA_HOME'), isFalse);
    },
  );
}

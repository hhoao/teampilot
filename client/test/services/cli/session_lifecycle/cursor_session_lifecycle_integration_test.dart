import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest_store.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/utils/team_member_naming.dart';

import '../../../support/cursor_lifecycle_test_paths.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  const workspaceId = 'ws';
  const sessionId = 'sess';
  const workingDirectory = '/home/hhoa/git/hhoa/teampilot';
  const slug = 'home-hhoa-git-hhoa-teampilot';

  late InMemoryFilesystem fs;
  late RuntimeLayout layout;
  late CliSessionManifestStore store;
  late CursorSessionLifecycleCapability capability;
  late CursorLifecycleTestPaths pathsDelegate;

  const busIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:9100/idle',
    sessionId: sessionId,
  );

  TeamProfile mixedCursorTeam() => TeamProfile(
    id: 'superpowers',
    name: 'Superpowers',
    cli: CliTool.cursor,
    teamMode: TeamMode.mixed,
    members: const [
      TeamMemberConfig(id: TeamMemberNaming.teamLeadName, name: 'Team Lead'),
      TeamMemberConfig(id: 'architect', name: 'Architect'),
    ],
  );

  CliSessionGateDecision gate(String memberId) {
    return capability.gateConnect(
      CliSessionGateContext(
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
        tool: CliTool.cursor,
        paths: pathsDelegate,
        team: mixedCursorTeam(),
        busIdle: busIdle,
      ),
    );
  }

  Future<void> seedMemberAuth(String memberId) async {
    final memberHome = layout.workspaceRuntimeMemberToolDir(
      workspaceId,
      'superpowers',
      memberId,
      'cursor',
    );
    final authDir = fs.pathContext.join(
      memberHome,
      'home',
      '.config',
      'cursor',
    );
    await fs.ensureDir(authDir);
    await fs.writeString(
      fs.pathContext.join(authDir, CursorHomeLayout.authFileName),
      '{"accessToken":"test","email":"user@example.com"}',
    );
  }

  setUp(() {
    fs = InMemoryFilesystem();
    layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    store = CliSessionManifestStore(fs: fs, layout: layout);
    capability = CursorSessionLifecycleCapability(manifestStore: store);
    pathsDelegate = CursorLifecycleTestPaths(fs: fs, layout: layout);
  });

  group('cursor session lifecycle integration', () {
    test('two members share projects dir and connect in parallel', () async {
      final team = mixedCursorTeam();
      await capability.ensurePersisted(
        CliSessionPersistContext(
          workspaceId: workspaceId,
          sessionId: sessionId,
          tool: CliTool.cursor,
          paths: pathsDelegate,
          team: team,
          workingDirectory: workingDirectory,
          busIdle: busIdle,
        ),
      );

      await seedMemberAuth(TeamMemberNaming.teamLeadName);
      await seedMemberAuth('architect');

      final leaderInit = await capability.initialize(
        CliSessionInitContext(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: TeamMemberNaming.teamLeadName,
          tool: CliTool.cursor,
          paths: pathsDelegate,
          team: team,
          busIdle: busIdle,
          workingDirectory: workingDirectory,
        ),
      );
      expect(leaderInit.phase, CliSessionPhase.ready);
      expect(leaderInit.blocked, isFalse);
      expect(gate(TeamMemberNaming.teamLeadName).allowed, isTrue);

      final architectInit = await capability.initialize(
        CliSessionInitContext(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: 'architect',
          tool: CliTool.cursor,
          paths: pathsDelegate,
          team: team,
          busIdle: busIdle,
          workingDirectory: workingDirectory,
        ),
      );
      expect(architectInit.phase, CliSessionPhase.ready);

      final followerGate = gate('architect');
      expect(followerGate.allowed, isTrue);

      final lifecyclePaths = CursorSessionLifecyclePaths(
        fs: fs,
        layout: layout,
        workspaceId: workspaceId,
        teamId: 'superpowers',
        workingDirectory: workingDirectory,
      );
      final sharedProjects = lifecyclePaths.sharedProjectsDir(slug);
      final leaderProjects = fs.pathContext.join(
        lifecyclePaths.memberCursorDir(
          lifecyclePaths.memberHomeRoot(TeamMemberNaming.teamLeadName),
        ),
        'projects',
      );
      expect(sharedProjects, isNotEmpty);
      expect(leaderProjects, isNotEmpty);

      expect(gate('architect').allowed, isTrue);

      final manifest = await store.read(
        workspaceId: workspaceId,
        teamId: 'superpowers',
        tool: CursorSessionLifecyclePaths.tool,
      );
      expect(manifest?.phase, CliSessionPhase.ready);
      expect(manifest?.shared.projectsDir, contains('/projects/$slug'));
    });
  });
}

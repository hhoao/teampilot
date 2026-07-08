import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest_store.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/utils/team_member_naming.dart';

import '../../../../support/cursor_warm_tier_manifest_paths.dart';
import '../../../../support/cursor_lifecycle_test_paths.dart';
import '../../../../support/in_memory_filesystem.dart';

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

  const oldBus = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:9100/idle',
    sessionId: sessionId,
  );
  const newBus = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:9200/idle',
    sessionId: sessionId,
  );

  setUp(() {
    fs = InMemoryFilesystem();
    layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    store = CliSessionManifestStore(fs: fs, layout: layout);
    capability = CursorSessionLifecycleCapability(manifestStore: store);
    pathsDelegate = CursorLifecycleTestPaths(fs: fs, layout: layout);
  });

  group('overlay generation stale gate and refresh', () {
    test('denies connect until initialize refreshes overlay', () async {
      final oldGen = CursorSessionLifecycleCapability.overlayGenerationForBus(
        oldBus,
      );
      await fs.ensureDir(
        layout.workspaceRuntimeToolDir(workspaceId, cursorTestTeamId, 'cursor'),
      );
      await fs.ensureDir(
        fs.pathContext.join(
          layout.workspaceRuntimeToolDir(workspaceId, cursorTestTeamId, 'cursor'),
          'projects',
          slug,
        ),
      );
      await store.write(
        workspaceId: workspaceId,
        teamId: cursorTestTeamId,
        tool: 'cursor',
        manifest: CliSessionManifest(
          tool: 'cursor',
          workspaceId: workspaceId,
          teamId: cursorTestTeamId,
          workspacePathHash: slug,
          workspaceSlug: slug,
          phase: CliSessionPhase.ready,
          shared: cursorTestSharedManifest(slug: slug),
          members: {
            TeamMemberNaming.teamLeadName: CliSessionManifestMember(
              homeRoot: cursorTestMemberHomeRelative(TeamMemberNaming.teamLeadName),
            ),
          },
          sessionOverlays: {
            sessionId: {
              TeamMemberNaming.teamLeadName: CliSessionManifestSessionOverlay(
                overlayGeneration: oldGen,
              ),
            },
          },
        ),
      );

      final memberHome = layout.workspaceRuntimeMemberToolDir(
        workspaceId,
        cursorTestTeamId,
        TeamMemberNaming.teamLeadName,
        'cursor',
      );
      final memberAuthDir = p.join(memberHome, 'home', '.config', 'cursor');
      await fs.ensureDir(memberAuthDir);
      await fs.writeString(
        p.join(memberAuthDir, CursorHomeLayout.authFileName),
        '{"accessToken":"test","email":"user@example.com"}',
      );

      final denied = capability.gateConnect(
        CliSessionGateContext(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: TeamMemberNaming.teamLeadName,
          tool: CliTool.cursor,
          paths: pathsDelegate,
          team: TeamProfile(
            id: cursorTestTeamId,
            name: 'Team',
            cli: CliTool.cursor,
            teamMode: TeamMode.mixed,
            members: const [
              TeamMemberConfig(
                id: TeamMemberNaming.teamLeadName,
                name: 'Lead',
              ),
            ],
          ),
          busIdle: newBus,
        ),
      );
      expect(denied.allowed, isFalse);
      expect(denied.reason, 'overlay');

      final init = await capability.initialize(
        CliSessionInitContext(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: TeamMemberNaming.teamLeadName,
          tool: CliTool.cursor,
          paths: pathsDelegate,
          team: TeamProfile(
            id: cursorTestTeamId,
            name: 'Team',
            cli: CliTool.cursor,
            teamMode: TeamMode.mixed,
            members: const [
              TeamMemberConfig(
                id: TeamMemberNaming.teamLeadName,
                name: 'Lead',
              ),
            ],
          ),
          busIdle: newBus,
          workingDirectory: workingDirectory,
        ),
      );
      expect(init.phase, CliSessionPhase.ready);

      final allowed = capability.gateConnect(
        CliSessionGateContext(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: TeamMemberNaming.teamLeadName,
          tool: CliTool.cursor,
          paths: pathsDelegate,
          team: TeamProfile(
            id: cursorTestTeamId,
            name: 'Team',
            cli: CliTool.cursor,
            teamMode: TeamMode.mixed,
            members: const [
              TeamMemberConfig(
                id: TeamMemberNaming.teamLeadName,
                name: 'Lead',
              ),
            ],
          ),
          busIdle: newBus,
        ),
      );
      expect(allowed.allowed, isTrue);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_context.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest_store.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/provider/cursor/cursor_cli_config_policy.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  const workspaceId = 'ws';
  const sessionId = 'sess';
  const workingDirectory = '/home/hhoa/git/hhoa/teampilot';
  const slug = 'home-hhoa-git-hhoa-teampilot';
  const providerId = 'official';

  late InMemoryFilesystem fs;
  late RuntimeLayout layout;
  late CliSessionManifestStore store;
  late CursorSessionLifecyclePaths lifecyclePaths;
  late CursorHomeLayout homeLayout;
  late _TestPaths pathsDelegate;
  late _RecordingAuthSync authSync;

  const busIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:9100/idle',
    sessionId: sessionId,
  );

  TeamProfile mixedCursorTeam() => TeamProfile(
    id: 'superpowers',
    name: 'Superpowers',
    cli: CliTool.cursor,
    teamMode: TeamMode.mixed,
    providerIdsByTool: const {'cursor': providerId},
    members: const [
      TeamMemberConfig(id: TeamMemberNaming.teamLeadName, name: 'Team Lead'),
      TeamMemberConfig(id: 'architect', name: 'Architect'),
    ],
  );

  CliSessionInitContext initContext({
    String memberId = TeamMemberNaming.teamLeadName,
    TeamProfile? team,
  }) {
    return CliSessionInitContext(
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      tool: CliTool.cursor,
      paths: pathsDelegate,
      team: team ?? mixedCursorTeam(),
      busIdle: busIdle,
      workingDirectory: workingDirectory,
    );
  }

  Future<CursorSessionLifecycleCapability> capability() async {
    return CursorSessionLifecycleCapability(
      manifestStore: store,
      authSync: authSync.call,
      resolveProviderId: (_) async => providerId,
    );
  }

  Future<void> seedPersisted() async {
    final cap = CursorSessionLifecycleCapability(
      manifestStore: store,
      authSync: authSync.call,
      resolveProviderId: (_) async => providerId,
    );
    await cap.ensurePersisted(
      CliSessionPersistContext(
        workspaceId: workspaceId,
        sessionId: sessionId,
        tool: CliTool.cursor,
        paths: pathsDelegate,
        team: mixedCursorTeam(),
        workingDirectory: workingDirectory,
        busIdle: busIdle,
      ),
    );
  }

  setUp(() {
    fs = InMemoryFilesystem();
    layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    store = CliSessionManifestStore(fs: fs, layout: layout);
    pathsDelegate = _TestPaths(fs: fs, layout: layout);
    homeLayout = CursorHomeLayout(pathContext: fs.pathContext);
    lifecyclePaths = CursorSessionLifecyclePaths(
      fs: fs,
      layout: layout,
      workspaceId: workspaceId,
      teamId: 'superpowers',
      workingDirectory: workingDirectory,
      homeLayout: homeLayout,
    );
    authSync = _RecordingAuthSync(fs: fs, layout: homeLayout);
  });

  group('CursorSessionLifecycleCapability.initialize', () {
    test('writes warm-tier base config from user cli-config.json', () async {
      await fs.writeString(
        homeLayout.cliConfig('/home/user'),
        jsonEncode({
          'serverConfigCache': {'feature': true},
          'network': {'proxy': 'http://127.0.0.1:7890'},
          'permissions': {
            'allow': [
              'Shell(ls)',
              CursorCliConfigPolicy.teamBusMcpAllowEntry,
            ],
          },
        }),
      );
      await seedPersisted();

      final cap = await capability();
      final result = await cap.initialize(initContext());

      expect(result.blocked, isFalse);
      final basePath = fs.pathContext.join(
        lifecyclePaths.sharedRoot(),
        'cli-config.base.json',
      );
      final base =
          jsonDecode((await fs.readString(basePath))!) as Map<String, Object?>;
      expect(base['serverConfigCache'], {'feature': true});
      expect(base['network'], {'proxy': 'http://127.0.0.1:7890'});
      final allow = (base['permissions']! as Map)['allow'] as List;
      expect(allow, contains('Shell(ls)'));
      expect(allow, isNot(contains(CursorCliConfigPolicy.teamBusMcpAllowEntry)));

      final manifest = await store.read(
        workspaceId: workspaceId,
        teamId: 'superpowers',
        tool: CursorSessionLifecyclePaths.tool,
      );
      expect(manifest!.phase, CliSessionPhase.ready);
    });

    test('provisions overlay with teammate-bus permissions and X-Member', () async {
      await seedPersisted();

      final cap = await capability();
      await cap.initialize(initContext());

      final memberHome = lifecyclePaths.memberHomeRoot(TeamMemberNaming.teamLeadName);
      final cliConfig =
          jsonDecode((await fs.readString(homeLayout.cliConfig(memberHome)))!)
              as Map<String, Object?>;
      final allow = (cliConfig['permissions']! as Map)['allow'] as List;
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));

      final mcp =
          jsonDecode((await fs.readString(homeLayout.mcpConfig(memberHome)))!)
              as Map<String, Object?>;
      final busServer =
          (mcp['mcpServers'] as Map)[teammateBusMcpServerName] as Map;
      final headers = (busServer['headers'] as Map).cast<String, String>();
      expect(headers[teammateBusMcpMemberHeader], TeamMemberNaming.teamLeadName);
    });

    test('syncs per-member auth from provider store', () async {
      await seedPersisted();

      final cap = await capability();
      await cap.initialize(initContext());

      expect(authSync.callCount, 1);
      final memberHome = lifecyclePaths.memberHomeRoot(TeamMemberNaming.teamLeadName);
      expect(
        await fs.readString(lifecyclePaths.memberAuthFile(memberHome)),
        isNotNull,
      );
      expect(
        (await fs.stat(homeLayout.configCursorDir(memberHome))).isDirectory,
        isTrue,
      );
    });

    test('initialize reaches ready for any roster member', () async {
      await seedPersisted();

      final cap = await capability();
      final result = await cap.initialize(initContext(memberId: 'architect'));

      expect(result.phase, CliSessionPhase.ready);
      expect(result.blocked, isFalse);
      final manifest = await store.read(
        workspaceId: workspaceId,
        teamId: 'superpowers',
        tool: CursorSessionLifecyclePaths.tool,
      );
      expect(manifest!.phase, CliSessionPhase.ready);
    });
  });
}

final class _RecordingAuthSync {
  _RecordingAuthSync({required this.fs, required this.layout});

  final Filesystem fs;
  final CursorHomeLayout layout;
  int callCount = 0;

  Future<void> call({
    required String providerId,
    required String memberAuthDir,
  }) async {
    callCount++;
    await fs.ensureDir(memberAuthDir);
    await fs.writeString(
      fs.pathContext.join(memberAuthDir, CursorHomeLayout.authFileName),
      '{"accessToken":"test","email":"user@example.com"}',
    );
  }
}

final class _TestPaths implements ConfigProfileDelegate {
  _TestPaths({required this.fs, required this.layout});

  @override
  final Filesystem fs;

  @override
  final RuntimeLayout layout;

  @override
  String get basePath => layout.teampilotRoot;

  @override
  String get home => '/home/user';

  @override
  p.Context get pathContext => fs.pathContext;

  @override
  String sessionToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) =>
      layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        tool,
        memberId: memberId,
      );

  @override
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) async =>
      Map<String, Object?>.from(defaults);

  @override
  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value) async {}

  @override
  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  }) async =>
      defaultMetadata;

  @override
  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  }) async =>
      false;

  @override
  Future<Map<String, Object?>> readSettingsFile(String path) async => {};

  @override
  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
    String? workspaceId,
  }) async {}

  @override
  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
    String? workspaceId,
  }) async =>
      false;

  @override
  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  }) async =>
      settings;

  @override
  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) async =>
      settings;

  @override
  Future<String?> resolveAppendSystemPromptPath({
    required LaunchProfileScope scope,
    required String tool,
    required TeamMemberConfig member,
  }) async =>
      null;

  @override
  HostExecutionEnvironment hostEnvironmentForProvision() =>
      HostExecutionEnvironment.resolve();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_context.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest_store.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/utils/team_member_naming.dart';

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
  late _TestPaths pathsDelegate;
  late CursorSessionLifecyclePaths lifecyclePaths;
  late CursorHomeLayout homeLayout;

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

  CliSessionPersistContext persistContext({TeamProfile? team}) {
    return CliSessionPersistContext(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: CliTool.cursor,
      paths: pathsDelegate,
      team: team ?? mixedCursorTeam(),
      workingDirectory: workingDirectory,
    );
  }

  setUp(() {
    fs = InMemoryFilesystem();
    layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    store = CliSessionManifestStore(fs: fs, layout: layout);
    capability = CursorSessionLifecycleCapability(manifestStore: store);
    pathsDelegate = _TestPaths(fs: fs, layout: layout);
    homeLayout = CursorHomeLayout(pathContext: fs.pathContext);
    lifecyclePaths = CursorSessionLifecyclePaths(
      fs: fs,
      layout: layout,
      workspaceId: workspaceId,
      sessionId: sessionId,
      workingDirectory: workingDirectory,
      homeLayout: homeLayout,
    );
  });

  group('CursorSessionLifecycleCapability.ensurePersisted', () {
    test('creates manifest, shared projects, and member project links', () async {
      await capability.ensurePersisted(persistContext());

      final manifest = await store.read(
        workspaceId: workspaceId,
        sessionId: sessionId,
        tool: CursorSessionLifecyclePaths.tool,
      );
      expect(manifest, isNotNull);
      expect(manifest!.phase, CliSessionPhase.persisted);
      expect(manifest.workspaceSlug, slug);
      expect(manifest.members.keys, containsAll(['team-lead', 'architect']));

      expect(
        (await fs.stat(lifecyclePaths.sharedProjectsDir())).isDirectory,
        isTrue,
      );

      final sharedProjectsRoot = fs.pathContext.join(
        lifecyclePaths.sharedRoot(),
        CursorWorkspaceTrust.projectsDirName,
      );

      for (final memberId in ['team-lead', 'architect']) {
        final memberHome = lifecyclePaths.memberHomeRoot(memberId);
        final memberProjects = fs.pathContext.join(
          homeLayout.cursorDir(memberHome),
          CursorWorkspaceTrust.projectsDirName,
        );
        expect(await fs.readSymlinkTarget(memberProjects), sharedProjectsRoot);
      }
    });

    test('is idempotent on second call', () async {
      final ctx = persistContext();
      await capability.ensurePersisted(ctx);
      final first = await store.read(
        workspaceId: workspaceId,
        sessionId: sessionId,
        tool: CursorSessionLifecyclePaths.tool,
      );

      await capability.ensurePersisted(ctx);
      final second = await store.read(
        workspaceId: workspaceId,
        sessionId: sessionId,
        tool: CursorSessionLifecyclePaths.tool,
      );

      expect(second, first);
    });

    test('adds new roster member without resetting existing entries', () async {
      await capability.ensurePersisted(
        persistContext(
          team: TeamProfile(
            id: 'superpowers',
            name: 'Superpowers',
            cli: CliTool.cursor,
            teamMode: TeamMode.mixed,
            members: const [
              TeamMemberConfig(
                id: TeamMemberNaming.teamLeadName,
                name: 'Team Lead',
              ),
            ],
          ),
        ),
      );
      final first = await store.read(
        workspaceId: workspaceId,
        sessionId: sessionId,
        tool: CursorSessionLifecyclePaths.tool,
      );

      await capability.ensurePersisted(persistContext());
      final second = await store.read(
        workspaceId: workspaceId,
        sessionId: sessionId,
        tool: CursorSessionLifecyclePaths.tool,
      );

      expect(second!.members.keys, containsAll(['team-lead', 'architect']));
      expect(
        second.members['team-lead'],
        first!.members['team-lead'],
      );
    });
  });
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

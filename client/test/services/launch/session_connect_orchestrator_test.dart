import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/launch/launch_manifest.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/launch/session_connect_orchestrator.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/launch/session_runtime_plan_builder.dart';
import 'package:teampilot/services/launch/workspace_provision_coordinator.dart';
import 'package:teampilot/services/launch/workspace_provisioner.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test(
    'prepareSimpleConnect applies staged writes via SessionScheduler, not ManifestExecutor.flush',
    () async {
      final posix = p.Context(style: p.Style.posix);
      final fs = InMemoryFilesystem(pathContext: posix);
      await fs.ensureDir('/work-tp');
      final storage = fakeHomeStorage(filesystem: fs, appDataRoot: '/work-tp');
      final workContext = RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/home/test',
        cwd: '/home/test',
        appDataRoot: '/work-tp',
        paths: AppPaths('/work-tp'),
      );
      final flushSpy = _FlushSpyManifestExecutor();
      final orchestrator = SessionConnectOrchestrator(
        lifecycle: _ConnectLifecycle(
          storage: storage,
          workContext: workContext,
        ),
        workspaceProvision: WorkspaceProvisionCoordinator(
          provisioner: _LocalCliProvisioner(),
          homeTarget: RuntimeTarget.local,
        ),
        configProfileFor: (_) async => _StagingProfile(storage: storage),
        homeContext: () => workContext,
        manifestExecutor: flushSpy,
        runtimePlanBuilder: _FixedSimplePlanBuilder(),
        registry: CliToolRegistry(),
      );

      await orchestrator.prepareSimpleConnect(
        session: AppSession(
          sessionId: 's',
          workspaceId: 'w',
          cli: CliTool.cursor,
          folders: const [WorkspaceFolder(path: '/proj')],
          createdAt: 1,
        ),
        workspace: Workspace(
          workspaceId: 'w',
          folders: const [WorkspaceFolder(path: '/proj')],
          createdAt: 1,
        ),
        launchTarget: RuntimeTarget.local(),
      );

      expect(await fs.readString('/work-tp/hello.txt'), 'from-stage');
      expect(flushSpy.flushCount, 0);
    },
  );
}

class _FlushSpyManifestExecutor extends ManifestExecutor {
  int flushCount = 0;

  @override
  Future<void> flush({
    required LaunchManifest manifest,
    required Filesystem targetFs,
    required Filesystem sourceFs,
    String? sshProfileId,
    String? symlinkProjectionRoot,
    String? homeRoot,
  }) async {
    flushCount += 1;
  }
}

class _StagingProfile extends ConfigProfileService {
  _StagingProfile({required super.storage})
    : super(basePath: '/work-tp', fs: storage.fs);

  @override
  Future<({TeamLaunchOutcome outcome, LaunchManifest manifest})>
  stageSimpleSessionLaunch({
    required Filesystem readDelegate,
    required String workTeampilotRoot,
    required String workspaceId,
    required String sessionId,
    required ConfigBundle runtimeBundle,
    required TeamMemberConfig member,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    WorkspaceBaseInfoPromptInputs workspaceBaseInfo =
        WorkspaceBaseInfoPromptInputs.empty,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    ResourceProviderSet injectedResourceProviders = ResourceProviderSet.empty,
  }) async {
    final manifest = LaunchManifest(pathContext: readDelegate.pathContext);
    manifest.writeFile('$workTeampilotRoot/hello.txt', 'from-stage');
    return (
      outcome: const TeamLaunchOutcome(environment: {'K': 'v'}),
      manifest: manifest,
    );
  }

  @override
  Future<void> provisionNativePlugins({
    required String workspaceId,
    required String sessionId,
    required ConfigBundle runtimeBundle,
    required CliTool cli,
    String? memberId,
    TeamProfile? team,
    String? executable,
  }) async {}
}

class _ConnectLifecycle extends SessionLifecycleService {
  _ConnectLifecycle({
    required super.storage,
    required this.workContext,
  }) : super(
         workContextResolver: (_) async => workContext,
         loadPresets: () => const [],
       );

  final RuntimeContext workContext;

  @override
  Future<ShellLaunchSpec> prepareShellLaunchFromEnvironmentPlan({
    required AppSession session,
    required Workspace workspace,
    required SessionRuntimePlan plan,
    TeamProfile? team,
    SessionMemberBinding? memberBinding,
    CliPreset? preset,
    required Map<String, String> environment,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    return ShellLaunchSpec.teamMember(
      team: const TeamProfile(id: 't', name: 't'),
      member: plan.member,
    );
  }
}

class _FixedSimplePlanBuilder extends SessionRuntimePlanBuilder {
  _FixedSimplePlanBuilder()
    : super(
        expertResolver: ExpertCapabilityResolver(
          installSkill: (_) async => null,
          installPlugin: (_) async => null,
          installMcp: (_) async => null,
          localStore: LocalExpertStore(
            fs: InMemoryFilesystem(),
            dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
          ),
        ),
        loadWorkspaceBundle: (_) async => const ConfigBundle(),
      );

  @override
  Future<SessionRuntimePlan> buildSimple({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    SimpleLaunchIdentity? identity,
    String? expertKey,
  }) async {
    return SessionRuntimePlan(
      mode: SessionRuntimeMode.simple,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      expertKey: expertKey ?? 'default',
      runtimeBundle: const ConfigBundle(),
      member: TeamMemberConfig(
        id: memberId,
        name: 'seat',
        cli: identity?.cli ?? CliTool.cursor,
      ),
    );
  }
}

class _LocalCliProvisioner implements WorkspaceProvisioner {
  @override
  Future<String> Function(CliTool cli) get localCliPath =>
      (_) async => '/bin/cursor-agent';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

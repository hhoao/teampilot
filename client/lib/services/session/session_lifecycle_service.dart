import 'package:flutter/foundation.dart';

import 'dart:io' show Platform;

import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_member_binding.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../models/member_instance.dart';
import '../../models/launch_profile.dart';
import '../../repositories/cli_presets_repository.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../models/config_bundle.dart';
import '../../utils/team/team_member_naming.dart';
import '../../utils/logging/logger.dart';
import '../../models/workspace_topology.dart';
import '../../models/workspace_launch_context.dart';
import '../team_bus/member_bus_idle_endpoint.dart';
import '../agent_status/member_agent_status_endpoint.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import '../storage/work_target_canonicalizer.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/capabilities/session_resume_capability.dart';
import '../cli/preset_resolver.dart';
import '../cli/cli_tool_adapter.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/flashskyai/capabilities/config_profile.dart';
import '../provider/control_plane_profile_paths.dart';
import '../provider/config_profile_service.dart';
import '../../models/runtime_target.dart';
import '../io/local_filesystem.dart';
import '../storage/runtime_context.dart';
import '../io/filesystem.dart';
import '../launch/layered_config_bundle.dart';
import '../launch/session_runtime_plan.dart';
import '../launch/session_runtime_plan_builder.dart';
import '../expert_hub/builtin_member_templates.dart';
import '../skill/skill_pack_install_store.dart';
import 'session_continue_overrides_apply.dart';
import 'shell_launch_spec.dart';

export 'shell_launch_spec.dart';

typedef StorageRootsResolver = Future<RuntimeContext> Function();

class SessionLifecycleService {
  static final _defaultCliRegistry = () {
    final registry = CliToolRegistry.builtIn();
    return registry;
  }();

  SessionLifecycleService({
    String? appDataBasePath,
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    Future<RuntimeContext> Function(RuntimeTarget target)? workContextResolver,
    Future<RuntimeContext> Function()? catalogContextResolver,
    Future<Set<String>> Function({String? teamId, String? workspaceId})?
    loadEnabledExtensionIds,
    CliToolRegistry? cliToolRegistry,
    LaunchProfileRepository? identityRepository,
    Future<List<Skill>> Function()? loadInstalledSkills,
    CliPresetsRepository? cliPresetsRepository,
    List<CliPreset> Function()? loadPresets,
    WorkspaceProjectConfigRepository? projectConfigRepository,
    SessionRuntimePlanBuilder? runtimePlanBuilder,
    RuntimeTarget Function()? homeTarget,
  }) : _appDataBasePath = appDataBasePath,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _workContextResolver = workContextResolver,
       _catalogContextResolver = catalogContextResolver,
       _loadEnabledExtensionIds = loadEnabledExtensionIds,
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry,
       _identityRepository = identityRepository,
       _loadInstalledSkills = loadInstalledSkills,
       _cliPresetsRepository = cliPresetsRepository,
       _loadPresets = loadPresets,
       _projectConfigRepository = projectConfigRepository,
       _runtimePlanBuilder = runtimePlanBuilder,
       _homeTarget = homeTarget ?? RuntimeTarget.local;

  final String? _appDataBasePath;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;

  /// P2: resolves the work-plane context for a workspace's target (local/wsl/
  /// ssh). When set, launch resolves runtime trees on the workspace's machine;
  /// session metadata still lives on home.
  final Future<RuntimeContext> Function(RuntimeTarget target)?
  _workContextResolver;

  /// Control-plane context (`registry.home()`). Provider catalog reads use this
  /// even when the member launches on a remote work machine.
  final Future<RuntimeContext> Function()? _catalogContextResolver;
  final Future<Set<String>> Function({String? teamId, String? workspaceId})?
  _loadEnabledExtensionIds;
  final CliToolRegistry _cliToolRegistry;
  final LaunchProfileRepository? _identityRepository;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  final CliPresetsRepository? _cliPresetsRepository;
  final List<CliPreset> Function()? _loadPresets;
  final WorkspaceProjectConfigRepository? _projectConfigRepository;
  final RuntimeTarget Function() _homeTarget;
  SessionRuntimePlanBuilder? _runtimePlanBuilder;

  /// Current app home target (local, SSH, or WSL).
  RuntimeTarget get currentHome => _homeTarget();

  /// Late-bind after bootstrap constructs [SessionRuntimePlanBuilder].
  void attachRuntimePlanBuilder(SessionRuntimePlanBuilder builder) {
    _runtimePlanBuilder = builder;
  }

  Future<ConfigBundle> _projectBundle(String workspaceId) async {
    final repo = _projectConfigRepository ?? WorkspaceProjectConfigRepository();
    return (await repo.load(workspaceId)).bundle;
  }

  /// Global CLI presets used by [resolveMemberLaunch] and launch validation.
  List<CliPreset> get globalPresets => _loadPresets?.call() ?? const [];

  CliToolRegistry get cliToolRegistry => _cliToolRegistry;

  /// Resolves a global CLI preset by id.
  Future<CliPreset?> resolvePresetById(String presetId) async {
    final trimmed = presetId.trim();
    if (trimmed.isEmpty) return null;
    final repo = _cliPresetsRepository;
    if (repo == null) return null;
    final presets = await repo.load();
    return resolveActivePreset(trimmed, presets);
  }

  Future<LaunchProfile?> loadIdentity(String profileId) async {
    final trimmed = profileId.trim();
    if (trimmed.isEmpty) return null;
    final repo = _identityRepository;
    if (repo == null) return null;
    final all = await repo.loadAll();
    for (final identity in all) {
      if (identity.id == trimmed) return identity;
    }
    return null;
  }

  Future<LaunchPlan> prepareLaunch({
    required AppSession session,
    required TeamProfile team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    return (await _prepareLaunchPlan(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    )).plan;
  }

  Future<ShellLaunchSpec> prepareShellLaunch({
    required AppSession session,
    required TeamProfile team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    final prepared = await _prepareLaunchPlan(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );

    return ShellLaunchSpec(
      plan: prepared.plan,
      launchContext: _buildShellLaunchContextFromPlan(
        session: session,
        plan: prepared.plan,
        runtimePlan: prepared.runtimePlan,
        workspace:
            workspace ??
            Workspace(
              workspaceId: session.workspaceId,
              folders: session.folders,
              createdAt: session.createdAt,
            ),
        team: team,
        preset: prepared.activePreset,
      ),
      sessionTeam: _resolveSessionTeam(session, prepared.plan, false),
    );
  }

  /// Prepare PTY [LaunchPlan] from an already-built [SessionRuntimePlan].
  Future<LaunchPlan> prepareLaunchFromRuntimePlan({
    required AppSession session,
    required Workspace workspace,
    required SessionRuntimePlan plan,
    TeamProfile? team,
    SessionMemberBinding? memberBinding,
    CliPreset? preset,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    return (await _prepareLaunchPlanFromRuntimePlan(
      session: session,
      workspace: workspace,
      plan: plan,
      team: team,
      memberBinding: memberBinding,
      preset: preset,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    )).plan;
  }

  /// Prepare [ShellLaunchSpec] from an already-built [SessionRuntimePlan].
  Future<ShellLaunchSpec> prepareShellLaunchFromRuntimePlan({
    required AppSession session,
    required Workspace workspace,
    required SessionRuntimePlan plan,
    TeamProfile? team,
    SessionMemberBinding? memberBinding,
    CliPreset? preset,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    final prepared = await _prepareLaunchPlanFromRuntimePlan(
      session: session,
      workspace: workspace,
      plan: plan,
      team: team,
      memberBinding: memberBinding,
      preset: preset,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );
    final isSimple = plan.mode == SessionRuntimeMode.simple;
    return ShellLaunchSpec(
      plan: prepared.plan,
      launchContext: _buildShellLaunchContextFromPlan(
        session: session,
        plan: prepared.plan,
        runtimePlan: plan,
        workspace: workspace,
        team: team,
        preset: prepared.activePreset,
      ),
      sessionTeam: _resolveSessionTeam(session, prepared.plan, isSimple),
    );
  }

  /// Builds [ShellLaunchSpec] after session config was applied on the work
  /// machine (Phase B). Consumes [SessionRuntimePlan] for member + bundle.
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
    final prepared = await _prepareLaunchPlanFromEnvironmentPlan(
      session: session,
      workspace: workspace,
      plan: plan,
      team: team,
      memberBinding: memberBinding,
      preset: preset,
      environment: environment,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );
    final isSimple = plan.mode == SessionRuntimeMode.simple;
    return ShellLaunchSpec(
      plan: prepared.plan,
      launchContext: _buildShellLaunchContextFromPlan(
        session: session,
        plan: prepared.plan,
        runtimePlan: plan,
        workspace: workspace,
        team: team,
        preset: prepared.activePreset,
      ),
      sessionTeam: _resolveSessionTeam(session, prepared.plan, isSimple),
    );
  }

  /// Builds [ShellLaunchSpec] for team sessions after config was applied on the
  /// work machine (Phase B). Only resolves resume ids and assembles launch context.
  Future<ShellLaunchSpec> prepareTeamShellLaunchFromEnvironment({
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    required Map<String, String> environment,
    List<String> launchWarnings = const [],
  }) async {
    final prepared = await _prepareTeamLaunchPlanFromEnvironment(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      environment: environment,
      launchWarnings: launchWarnings,
    );

    final resolvedWorkspace =
        workspace ??
        Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: session.createdAt,
        );
    final runtimePlan = SessionRuntimePlan(
      mode: SessionRuntimeMode.team,
      workspaceId: resolvedWorkspace.workspaceId,
      sessionId: session.sessionId,
      memberId: member.id,
      expertKey: member.agentType.trim().isNotEmpty
          ? member.agentType
          : (member.agent.trim().isNotEmpty ? member.agent : member.id),
      teamId: team.id,
      runtimeBundle: team.bundle,
      member: prepared.resolvedMember,
    );

    return ShellLaunchSpec(
      plan: prepared.plan,
      launchContext: _buildShellLaunchContextFromPlan(
        session: session,
        plan: prepared.plan,
        runtimePlan: runtimePlan,
        workspace: resolvedWorkspace,
        team: team,
      ),
      sessionTeam: _resolveSessionTeam(session, prepared.plan, false),
    );
  }

  /// Manifest-backed team env for previews and external launchers (local work fs).
  ///
  /// Builds a [SessionRuntimePlan] per seat so provision uses the merged
  /// expert/team/workspace [ConfigBundle], not workspace-only.
  Future<TeamLaunchOutcome> prepareTeamLaunchEnvironment({
    required TeamProfile team,
    TeamMemberConfig? member,
    String workspaceId = '',
    String sessionId = '',
    String workingDirectory = '',
  }) async {
    final roots = await _resolveRoots();
    final service = await _configProfileServiceFor(roots);
    final trimmedTeamId = team.id.trim();
    if (trimmedTeamId.isEmpty) {
      return const TeamLaunchOutcome(environment: {});
    }
    final trimmedSessionId = sessionId.trim().isNotEmpty
        ? sessionId.trim()
        : trimmedTeamId;
    final launchMember =
        member ??
        team.members.firstWhere(
          (m) => m.isValid,
          orElse: () => const TeamMemberConfig(id: '', name: ''),
        );
    final trimmedWorkspaceId = workspaceId.trim();
    final runtimeBundle = await _runtimeBundleForTeamPreview(
      team: team,
      member: launchMember,
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
    );
    return service.prepareTeamLaunch(
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      teamId: trimmedTeamId,
      cliTeamName: trimmedTeamId,
      cli: launchMember.isValid
          ? memberLaunchCli(
              team: team,
              member: launchMember,
              globalPresets: _loadPresets?.call() ?? const [],
            )
          : team.cli,
      members: runtimeRosterMembers(team),
      member: launchMember.isValid ? launchMember : null,
      workingDirectory: workingDirectory.isNotEmpty
          ? workingDirectory
          : AppStorage.cwd,
      team: team,
      runtimeBundle: runtimeBundle,
    );
  }

  Future<ConfigBundle> _runtimeBundleForTeamPreview({
    required TeamProfile team,
    required TeamMemberConfig member,
    required String workspaceId,
    required String sessionId,
  }) async {
    final builder = _runtimePlanBuilder;
    if (builder != null && workspaceId.isNotEmpty && member.isValid) {
      final plan = await builder.buildTeamSeat(
        workspaceId: workspaceId,
        sessionId: sessionId,
        team: team,
        slot: teamRosterSlotForMember(team, member),
        presetId: member.activePresetId,
        member: member,
      );
      return plan.runtimeBundle;
    }
    // Preview without workspace / plan builder: team bundle only (no
    // workspace-only bypass that drops expert/team merge).
    if (workspaceId.isEmpty) {
      return team.bundle;
    }
    final workspaceBundle = await _projectBundle(workspaceId);
    return LayeredConfigBundle.merge(
      team: team.bundle,
      workspace: workspaceBundle,
    );
  }

  TeamMemberConfig? _resolveTeamMemberForLaunch(
    TeamProfile team,
    TeamMemberConfig member,
  ) {
    return memberForLaunch(
      team: team,
      member: member,
      globalPresets: _loadPresets?.call() ?? const [],
    );
  }

  Future<
    ({
      LaunchPlan plan,
      CliPreset? activePreset,
      TeamMemberConfig resolvedMember,
    })
  >
  _prepareLaunchPlanFromRuntimePlan({
    required AppSession session,
    required Workspace workspace,
    required SessionRuntimePlan plan,
    TeamProfile? team,
    SessionMemberBinding? memberBinding,
    CliPreset? preset,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    final sessionId = session.sessionId.trim();
    final isSimple = plan.mode == SessionRuntimeMode.simple;
    final launchMember = isSimple
        ? plan.member
        : _memberWithPreset(plan.member, preset);
    final taskId = isSimple
        ? sessionId
        : (memberBinding?.taskId.trim().isNotEmpty == true
              ? memberBinding!.taskId.trim()
              : sessionId);
    final memberWork = session.workDirsForMember(
      isSimple ? null : (memberBinding?.rosterMemberId ?? launchMember.id),
      folders: workspace.folders,
    );

    appLogger.d(
      '[session-lifecycle] prepareLaunchFromRuntimePlan start '
      'session=$sessionId mode=${plan.mode.name} member=${launchMember.id}',
    );

    final roots = await _resolveRoots(
      session: session,
      memberId: isSimple
          ? null
          : (memberBinding?.rosterMemberId ?? launchMember.id),
    );
    final service = await _configProfileServiceFor(
      roots,
      launchWorkspaceId: isSimple ? workspace.workspaceId : null,
    );

    final activePreset = isSimple
        ? null
        : preset ??
              (plan.presetId != null && plan.presetId!.trim().isNotEmpty
                  ? await resolvePresetById(plan.presetId!)
                  : null);
    final memberForLaunch = isSimple
        ? launchMember
        : _memberWithPreset(launchMember, activePreset);

    final cliTeamName = session.cliTeamName.trim();
    final runtimeTeamId = isSimple
        ? sessionId
        : (cliTeamName.isNotEmpty ? cliTeamName : sessionId);
    final cli = isSimple
        ? (session.cli ??
              memberForLaunch.cli ??
              activePreset?.cli ??
              CliTool.claude)
        : (team != null
              ? _memberLaunchCli(team, memberForLaunch, session: session)
              : (memberForLaunch.cli ?? CliTool.claude));
    final tools = [cli.value];
    final teamId = (team?.id ?? plan.teamId ?? session.sessionTeam).trim();

    final transcriptRoots = isSimple
        ? _standaloneTranscriptSearchRoots(
            layout: roots.layout,
            workspaceId: workspace.workspaceId,
            sessionId: sessionId,
            tools: tools,
          )
        : roots.layout.transcriptSearchRoots(
            workspaceId: session.workspaceId.trim(),
            sessionId: session.sessionId.trim(),
            profileId: teamId,
            tools: tools,
          );

    final prepared = await _prepareEnvFromRuntimePlan(
      service: service,
      session: session,
      workspace: workspace,
      plan: plan,
      team: team,
      member: memberForLaunch,
      memberBinding: memberBinding,
      runtimeTeamId: runtimeTeamId,
      workingDirectory: memberWork.workingDirectory,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );
    final packStore = SkillPackInstallStore();
    final packPaths = await packStore.pathExportsForSkills(
      plan.runtimeBundle.skillIds,
    );
    final packEnv = await packStore.envExportsForSkills(
      plan.runtimeBundle.skillIds,
    );
    final launchEnv = SkillPackInstallStore.mergeEnvExports(
      SkillPackInstallStore.prependPath(
        prepared.env,
        packPaths,
        platformPath: Platform.environment['PATH'],
        isWindows: Platform.isWindows,
      ),
      packEnv,
    );

    final memberConfigDir = _memberConfigDirFromEnv(launchEnv);
    final rootsForResume = <String>{
      ...transcriptRoots,
      if (memberConfigDir.isNotEmpty) memberConfigDir,
    }.toList(growable: false);

    final resume = await _resolveResume(
      roots: roots,
      cli: cli,
      taskId: taskId,
      env: launchEnv,
      transcriptRoots: rootsForResume,
      bucket: RuntimeLayout.workspaceBucketForPrimaryPath(
        memberWork.workingDirectory,
      ),
      persistedNativeId: isSimple
          ? session.nativeSessionIds[cli.value]
          : memberBinding?.nativeSessionIds[cli.value],
      previouslyLaunched: session.launchState == AppSessionLaunchState.started,
      workspaceId: session.workspaceId,
      sessionId: sessionId,
      memberId: isSimple
          ? null
          : (memberBinding?.rosterMemberId ?? memberForLaunch.id),
      teamId: isSimple ? null : teamId,
    );

    final launchPlan = LaunchPlan(
      env: launchEnv,
      resume: resume.resumeSessionId != null,
      taskId: taskId,
      createSessionId: resume.createSessionId,
      resumeSessionId: resume.resumeSessionId,
      nativeSessionIdToPersist: resume.nativeSessionIdToPersist,
      toolValue: cli.value,
      cliTeamName: runtimeTeamId,
      memberConfigDir: memberConfigDir,
      resolvedRoots: rootsForResume,
      warnings: prepared.warnings,
    );

    appLogger.d(
      '[session-lifecycle] prepareLaunchFromRuntimePlan ready '
      'session=$sessionId resume=${launchPlan.resume}',
    );

    return (
      plan: launchPlan,
      activePreset: activePreset,
      resolvedMember: memberForLaunch,
    );
  }

  Future<
    ({
      LaunchPlan plan,
      CliPreset? activePreset,
      TeamMemberConfig resolvedMember,
    })
  >
  _prepareLaunchPlanFromEnvironmentPlan({
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
    final sessionId = session.sessionId.trim();
    final isSimple = plan.mode == SessionRuntimeMode.simple;
    final launchMember = isSimple
        ? plan.member
        : _memberWithPreset(plan.member, preset);
    final taskId = isSimple
        ? sessionId
        : (memberBinding?.taskId.trim().isNotEmpty == true
              ? memberBinding!.taskId.trim()
              : sessionId);
    final memberWork = session.workDirsForMember(
      isSimple ? null : (memberBinding?.rosterMemberId ?? launchMember.id),
      folders: workspace.folders,
    );

    final roots = await _resolveRoots(
      session: session,
      memberId: isSimple
          ? null
          : (memberBinding?.rosterMemberId ?? launchMember.id),
    );
    final activePreset = isSimple
        ? null
        : preset ??
              (plan.presetId != null && plan.presetId!.trim().isNotEmpty
                  ? await resolvePresetById(plan.presetId!)
                  : null);
    final memberForLaunch = isSimple
        ? launchMember
        : _memberWithPreset(launchMember, activePreset);
    final cliTeamName = session.cliTeamName.trim();
    final runtimeTeamId = isSimple
        ? sessionId
        : (cliTeamName.isNotEmpty ? cliTeamName : sessionId);
    final cli = isSimple
        ? (session.cli ??
              memberForLaunch.cli ??
              activePreset?.cli ??
              CliTool.claude)
        : (team != null
              ? _memberLaunchCli(team, memberForLaunch, session: session)
              : (memberForLaunch.cli ?? CliTool.claude));
    final tools = [cli.value];
    final teamId = (team?.id ?? plan.teamId ?? session.sessionTeam).trim();
    final transcriptRoots = isSimple
        ? _standaloneTranscriptSearchRoots(
            layout: roots.layout,
            workspaceId: workspace.workspaceId,
            sessionId: sessionId,
            tools: tools,
          )
        : roots.layout.transcriptSearchRoots(
            workspaceId: session.workspaceId.trim(),
            sessionId: session.sessionId.trim(),
            profileId: teamId,
            tools: tools,
          );
    final packStore = SkillPackInstallStore();
    final packPaths = await packStore.pathExportsForSkills(
      plan.runtimeBundle.skillIds,
    );
    final packEnv = await packStore.envExportsForSkills(
      plan.runtimeBundle.skillIds,
    );
    final launchEnv = SkillPackInstallStore.mergeEnvExports(
      SkillPackInstallStore.prependPath(
        environment,
        packPaths,
        platformPath: Platform.environment['PATH'],
        isWindows: Platform.isWindows,
      ),
      packEnv,
    );
    final memberConfigDir = _memberConfigDirFromEnv(launchEnv);
    final rootsForResume = <String>{
      ...transcriptRoots,
      if (memberConfigDir.isNotEmpty) memberConfigDir,
    }.toList(growable: false);

    final resume = await _resolveResume(
      roots: roots,
      cli: cli,
      taskId: taskId,
      env: launchEnv,
      transcriptRoots: rootsForResume,
      bucket: RuntimeLayout.workspaceBucketForPrimaryPath(
        memberWork.workingDirectory,
      ),
      persistedNativeId: isSimple
          ? session.nativeSessionIds[cli.value]
          : memberBinding?.nativeSessionIds[cli.value],
      previouslyLaunched: session.launchState == AppSessionLaunchState.started,
      workspaceId: isSimple ? workspace.workspaceId : session.workspaceId,
      sessionId: sessionId,
      memberId: isSimple
          ? null
          : (memberBinding?.rosterMemberId ?? memberForLaunch.id),
      teamId: isSimple ? null : teamId,
    );

    final launchPlan = LaunchPlan(
      env: launchEnv,
      resume: resume.resumeSessionId != null,
      taskId: taskId,
      createSessionId: resume.createSessionId,
      resumeSessionId: resume.resumeSessionId,
      nativeSessionIdToPersist: resume.nativeSessionIdToPersist,
      toolValue: cli.value,
      cliTeamName: runtimeTeamId,
      memberConfigDir: memberConfigDir,
      resolvedRoots: rootsForResume,
      warnings: const [],
    );

    return (
      plan: launchPlan,
      activePreset: activePreset,
      resolvedMember: memberForLaunch,
    );
  }

  Future<_PreparedLaunch> _prepareEnvFromRuntimePlan({
    required ConfigProfileService service,
    required AppSession session,
    required Workspace workspace,
    required SessionRuntimePlan plan,
    TeamProfile? team,
    required TeamMemberConfig member,
    SessionMemberBinding? memberBinding,
    required String runtimeTeamId,
    required String workingDirectory,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    final catalog = WorkspaceLaunchContext(
      session: session,
      workspace: workspace,
    ).folderCatalog;
    final memberDirs = session.workDirsForMember(
      plan.mode == SessionRuntimeMode.simple
          ? null
          : (memberBinding?.rosterMemberId ?? member.id),
      folders: catalog,
    );
    final cwd = workingDirectory.isNotEmpty
        ? workingDirectory
        : memberDirs.workingDirectory;

    if (plan.mode == SessionRuntimeMode.simple) {
      final outcome = await service.prepareSimpleSessionLaunch(
        workspaceId: workspace.workspaceId,
        sessionId: session.sessionId,
        runtimeBundle: plan.runtimeBundle,
        member: member,
        workingDirectory: cwd,
        additionalDirectories: memberDirs.addDirs,
        extraMcpServers: extraMcpServers,
        busIdle: busIdle,
        agentStatus: agentStatus,
      );
      return _PreparedLaunch(
        env: outcome.environment,
        warnings: outcome.warnings,
      );
    }

    final teamId = (team?.id ?? plan.teamId ?? '').trim();
    if (team == null || teamId.isEmpty) {
      throw StateError('Team SessionRuntimePlan requires team');
    }
    final launchCli = _memberLaunchCli(team, member, session: session);
    final leadTaskId = memberBinding?.taskId.trim() ?? '';
    final leadSessionId =
        TeamMemberNaming.isTeamLead(member) && leadTaskId.isNotEmpty
            ? leadTaskId
            : null;
    final outcome = await service.prepareTeamLaunch(
      workspaceId: effectiveLaunchWorkspaceId(
        workspaceId: session.workspaceId,
        teamId: teamId,
      ),
      sessionId: session.sessionId.trim(),
      teamId: teamId,
      cliTeamName: runtimeTeamId,
      cli: launchCli,
      members: cliTeamRosterMembers(session, team),
      member: member,
      workingDirectory: memberDirs.workingDirectory.isNotEmpty
          ? memberDirs.workingDirectory
          : cwd,
      additionalDirectories: memberDirs.addDirs,
      team: team,
      runtimeBundle: plan.runtimeBundle,
      leadSessionId: leadSessionId,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );
    return _PreparedLaunch(
      env: outcome.environment,
      warnings: outcome.warnings,
    );
  }

  CliLaunchContext _buildShellLaunchContextFromPlan({
    required AppSession session,
    required LaunchPlan plan,
    required SessionRuntimePlan runtimePlan,
    required Workspace workspace,
    TeamProfile? team,
    CliPreset? preset,
  }) {
    final isSimple = runtimePlan.mode == SessionRuntimeMode.simple;
    // Overrides must stay last: preset may re-run even when plan.member was
    // already finalized in SessionConnectOrchestrator.
    final member = finalizeSessionLaunchMember(
      session: session,
      baseMember: runtimePlan.member,
      memberId: isSimple ? session.sessionId : runtimePlan.memberId,
      isSimple: isSimple,
      preset: preset,
      withPreset: _memberWithPreset,
    );
    final catalog = WorkspaceLaunchContext(
      session: session,
      workspace: workspace,
    ).folderCatalog;

    if (runtimePlan.mode == SessionRuntimeMode.simple) {
      final personalDirs = session.workDirsForMember(null, folders: catalog);
      final launchTeam = TeamProfile(
        id: workspace.workspaceId,
        name: plan.cliTeamName.trim().isNotEmpty
            ? plan.cliTeamName.trim()
            : session.sessionId,
        cli: member.cli ?? session.cli ?? CliTool.claude,
        members: [member],
        skillIds: runtimePlan.runtimeBundle.skillIds,
        pluginIds: runtimePlan.runtimeBundle.pluginIds,
        mcpServerIds: runtimePlan.runtimeBundle.mcpServerIds,
        teamMode: TeamMode.native,
        forceTeamLeadDelegateMode: false,
      );
      return CliLaunchContext(
        team: launchTeam,
        member: member,
        sessionTeam: plan.cliTeamName,
        workingDirectory: personalDirs.workingDirectory,
        additionalDirectories: personalDirs.addDirs,
        // Synthetic 1-member native profile is argv plumbing only — do not
        // enable Claude agent-team "manual mode" (causes multi-call loops).
        nativeAgentTeam: false,
      );
    }

    if (team == null) {
      throw StateError(
        'prepareShellLaunch requires team for team SessionRuntimePlan',
      );
    }
    final memberDirs = session.workDirsForMember(member.id, folders: catalog);
    final launchTeam = team.copyWith(
      skillIds: runtimePlan.runtimeBundle.skillIds,
      pluginIds: runtimePlan.runtimeBundle.pluginIds,
      mcpServerIds: runtimePlan.runtimeBundle.mcpServerIds,
    );
    return CliLaunchContext(
      team: launchTeam,
      member: member,
      sessionTeam: _resolveSessionTeam(session, plan, false),
      workingDirectory: memberDirs.workingDirectory.isNotEmpty
          ? memberDirs.workingDirectory
          : session.firstFolderPath,
      additionalDirectories: memberDirs.addDirs,
    );
  }

  TeamMemberConfig _memberWithPreset(
    TeamMemberConfig member,
    CliPreset? preset,
  ) {
    if (preset == null) return member;
    return member.copyWith(
      provider: preset.provider.trim().isNotEmpty
          ? preset.provider.trim()
          : member.provider,
      model: preset.model.trim().isNotEmpty ? preset.model.trim() : member.model,
      effort: preset.effort.trim().isNotEmpty
          ? preset.effort.trim()
          : member.effort,
      cli: preset.cli,
      updateCli: true,
    );
  }

  Future<({LaunchPlan plan, TeamMemberConfig resolvedMember})>
  _prepareTeamLaunchPlanFromEnvironment({
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    required Map<String, String> environment,
    List<String> launchWarnings = const [],
  }) async {
    final sessionId = session.sessionId.trim();
    final teamId = team.id.trim();
    final cliTeamName = session.cliTeamName.trim();
    final taskId = memberBinding?.taskId.trim() ?? sessionId;
    final launchMember = _resolveTeamMemberForLaunch(team, member) ?? member;

    appLogger.d(
      '[session-lifecycle] prepareTeamLaunchFromEnvironment start '
      'session=$sessionId team=$teamId member=${member.id}',
    );

    final roots = await _resolveRoots(
      session: session,
      memberId: memberBinding?.rosterMemberId,
      workspace: workspace,
    );
    final runtimeTeamId = cliTeamName.isNotEmpty ? cliTeamName : sessionId;
    final cli = _memberLaunchCli(team, launchMember, session: session);
    final catalog = workspace != null
        ? WorkspaceLaunchContext(
            session: session,
            workspace: workspace,
          ).folderCatalog
        : session.folders;
    final memberDirs = session.workDirsForMember(
      memberBinding?.rosterMemberId ?? member.id,
      folders: catalog,
    );
    final transcriptRoots = roots.layout.transcriptSearchRoots(
      workspaceId: session.workspaceId.trim(),
      sessionId: sessionId,
      profileId: teamId,
      tools: [cli.value],
    );
    final memberConfigDir = _memberConfigDirFromEnv(environment);
    final rootsForResume = <String>{
      ...transcriptRoots,
      if (memberConfigDir.isNotEmpty) memberConfigDir,
    }.toList(growable: false);

    final resume = await _resolveResume(
      roots: roots,
      cli: cli,
      taskId: taskId,
      env: environment,
      transcriptRoots: rootsForResume,
      bucket: RuntimeLayout.workspaceBucketForPrimaryPath(
        memberDirs.workingDirectory,
      ),
      persistedNativeId: memberBinding?.nativeSessionIds[cli.value],
      previouslyLaunched: session.launchState == AppSessionLaunchState.started,
      workspaceId: session.workspaceId,
      sessionId: sessionId,
      memberId: memberBinding?.rosterMemberId ?? member.id,
      teamId: teamId,
    );

    final plan = LaunchPlan(
      env: environment,
      resume: resume.resumeSessionId != null,
      taskId: taskId,
      createSessionId: resume.createSessionId,
      resumeSessionId: resume.resumeSessionId,
      nativeSessionIdToPersist: resume.nativeSessionIdToPersist,
      toolValue: cli.value,
      cliTeamName: runtimeTeamId,
      memberConfigDir: memberConfigDir,
      resolvedRoots: rootsForResume,
      warnings: launchWarnings,
    );

    appLogger.d(
      '[session-lifecycle] prepareTeamLaunchFromEnvironment ready '
      'session=$sessionId resume=${plan.resume}',
    );

    return (plan: plan, resolvedMember: launchMember);
  }

  Future<
    ({
      LaunchPlan plan,
      SessionRuntimePlan runtimePlan,
      CliPreset? activePreset,
      TeamMemberConfig resolvedMember,
    })
  >
  _prepareLaunchPlan({
    required AppSession session,
    required TeamProfile team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    final teamId = team.id.trim();
    if (teamId.isEmpty) {
      throw StateError('prepareLaunch requires a team identity');
    }
    final resolvedWorkspace =
        workspace ??
        Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: session.createdAt,
        );
    final launchMember =
        member != null
            ? (_resolveTeamMemberForLaunch(team, member) ?? member)
            : team.members.firstWhere(
                (m) => m.isValid,
                orElse: () => const TeamMemberConfig(id: '', name: ''),
              );
    if (!launchMember.isValid) {
      throw StateError('prepareLaunch requires a valid team member');
    }

    final rosterId =
        memberBinding?.rosterMemberId.trim() ?? launchMember.id.trim();
    if (rosterId.isNotEmpty) {
      if (workspaceNeedsMixedPlacementInit(
        folders: resolvedWorkspace.folders,
        teamId: teamId,
        initializedByTeam: resolvedWorkspace.memberPlacementInitializedByTeam,
      )) {
        throw StateError('mixed_workspace_member_placement_uninitialized');
      }
      final bound = session.members.any((b) => b.rosterMemberId == rosterId);
      final hasPin =
          memberTargetForInstanceId(session.memberTargets, rosterId) != null;
      final mustValidatePin =
          bound &&
          (workspaceTopologyOf(resolvedWorkspace.folders) ==
                  WorkspaceTopology.mixed ||
              hasPin);
      if (mustValidatePin &&
          !memberTargetIsValid(
            WorkspaceLaunchContext(
              session: session,
              workspace: resolvedWorkspace,
            ),
            rosterId,
          )) {
        throw StateError(
          'Member target assignment is invalid '
          '(member=$rosterId target=${session.memberTargets[rosterId]})',
        );
      }
    }

    final runtimePlan = await _buildTeamRuntimePlan(
      session: session,
      workspace: resolvedWorkspace,
      team: team,
      member: launchMember,
    );

    final prepared = await _prepareLaunchPlanFromRuntimePlan(
      session: session,
      workspace: resolvedWorkspace,
      plan: runtimePlan,
      team: team,
      memberBinding: memberBinding,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );
    return (
      plan: prepared.plan,
      runtimePlan: runtimePlan,
      activePreset: prepared.activePreset,
      resolvedMember: prepared.resolvedMember,
    );
  }

  Future<SessionRuntimePlan> _buildTeamRuntimePlan({
    required AppSession session,
    required Workspace workspace,
    required TeamProfile team,
    required TeamMemberConfig member,
  }) async {
    final builder = _runtimePlanBuilder;
    if (builder != null) {
      return builder.buildTeamSeat(
        workspaceId: workspace.workspaceId,
        sessionId: session.sessionId,
        team: team,
        slot: teamRosterSlotForMember(team, member),
        presetId: member.activePresetId,
        member: member,
      );
    }
    final workspaceBundle = await _projectBundle(workspace.workspaceId);
    return SessionRuntimePlan(
      mode: SessionRuntimeMode.team,
      workspaceId: workspace.workspaceId,
      sessionId: session.sessionId,
      memberId: member.id,
      expertKey: kBuiltinDefaultExpertKey,
      teamId: team.id,
      presetId: member.activePresetId,
      runtimeBundle: LayeredConfigBundle.merge(
        team: team.bundle,
        workspace: workspaceBundle,
      ),
      member: member,
    );
  }

  Future<bool> hasCliState(
    AppSession session, {
    String? teamId,
    CliTool? cli,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
  }) async {
    final roots = await _resolveRoots(
      session: session,
      memberId: memberBinding?.rosterMemberId,
    );
    final isPersonal = _isPersonalLaunch(workspace, session);
    final runtimeTeamId = isPersonal
        ? session.sessionId.trim()
        : session.cliTeamName.trim().isNotEmpty
        ? session.cliTeamName.trim()
        : session.sessionId.trim();
    final cliSessionId =
        memberBinding?.taskId.trim() ?? session.sessionId.trim();
    CliTool? resolvedCli;
    if (isPersonal) {
      resolvedCli = session.cli ?? CliTool.claude;
    } else {
      resolvedCli = cli;
    }
    final probe = await _findCliState(
      roots: roots,
      session: session,
      teamId: (teamId ?? session.sessionTeam).trim(),
      runtimeSessionId: runtimeTeamId,
      cliSessionId: cliSessionId,
      cli: resolvedCli,
      workspaceId: isPersonal ? workspace!.workspaceId : null,
    );
    return probe.exists;
  }

  Future<void> destroyCliState({
    required String workspaceId,
    required String teamId,
    required String sessionId,
    AppSession? session,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedSessionId.isEmpty) {
      return;
    }

    // P2: clean the runtime tree on the *workspace's* machine (work plane),
    // resolved from the session's folder target, not always home.
    final roots = await _resolveRoots(session: session);
    final sessionRoot = roots.layout.workspace.sessionRuntimeDir(
      trimmedWorkspaceId,
      trimmedSessionId,
    );
    await _removeTree(roots, sessionRoot);
  }

  Future<void> destroyStandaloneCliState({
    required String workspaceId,
    required String sessionId,
    AppSession? session,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) return;

    final roots = await _resolveRoots(session: session);
    final sessionRoot = roots.layout.workspace.sessionRuntimeDir(
      trimmedWorkspaceId,
      trimmedSessionId,
    );
    await _removeTree(roots, sessionRoot);
  }

  Future<void> destroyCliToolState(String teamId) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) return;

    final roots = await _resolveRoots();
    final teamRoot = roots.fs.pathContext.dirname(
      roots.layout.identityToolDir(trimmedTeamId, 'flashskyai'),
    );
    await _removeTree(roots, teamRoot);
  }

  bool _isPersonalLaunch(Workspace? workspace, AppSession session) =>
      workspace != null && session.sessionTeam.trim().isEmpty;

  /// Test-only seam for [_isPersonalLaunch].
  @visibleForTesting
  bool debugIsPersonalLaunch(Workspace workspace, AppSession session) =>
      _isPersonalLaunch(workspace, session);

  String _resolveSessionTeam(
    AppSession session,
    LaunchPlan plan,
    bool isPersonal,
  ) {
    if (isPersonal) return plan.cliTeamName;
    final fromSession = session.cliTeamName.trim();
    if (fromSession.isNotEmpty) return fromSession;
    return plan.cliTeamName;
  }

  List<String> _standaloneTranscriptSearchRoots({
    required RuntimeLayout layout,
    required String workspaceId,
    required String sessionId,
    required Iterable<String> tools,
  }) {
    final tt = tools.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [
      for (final tool in tt) layout.appToolRoot(tool),
      for (final tool in tt) layout.workspaceConfigToolDir(workspaceId, tool),
      for (final tool in tt)
        layout.sessionRuntimeToolDir(workspaceId, sessionId, tool),
    ];
  }

  Future<ConfigProfileService> configProfileServiceFor(
    RuntimeContext roots, {
    String? launchWorkspaceId,
  }) => _configProfileServiceFor(roots, launchWorkspaceId: launchWorkspaceId);

  Future<ConfigProfileService> _configProfileServiceFor(
    RuntimeContext roots, {
    String? launchWorkspaceId,
  }) async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    final loader = _loadEnabledExtensionIds;
    final trimmedWorkspaceId = launchWorkspaceId?.trim() ?? '';
    final catalogRoots = await _resolveCatalogRoots();
    final catalog = catalogRoots.appDataRoot == roots.appDataRoot
        ? null
        : ControlPlaneProfilePaths(catalogRoots);
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      home: roots.home,
      fs: roots.fs,
      layout: roots.layout,
      catalog: catalog,
      loadEnabledExtensionIds: loader == null
          ? null
          : ({teamId, workspaceId}) => loader(
              teamId: teamId,
              workspaceId: (workspaceId?.trim().isNotEmpty ?? false)
                  ? workspaceId
                  : (trimmedWorkspaceId.isNotEmpty ? trimmedWorkspaceId : null),
            ),
      cliRegistry: _cliToolRegistry,
      loadInstalledSkills: _loadInstalledSkills,
      loadGlobalPresets: () async => _loadPresets?.call() ?? const [],
    );
  }

  Future<RuntimeContext> _resolveCatalogRoots() async {
    final resolver = _catalogContextResolver ?? _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(_appDataBasePath ?? AppStorage.paths.basePath);
  }

  /// Test seam: resolve the work-plane context for [session] (and optionally a
  /// [memberId], exercising the per-member folder-target → forTarget path).
  @visibleForTesting
  Future<RuntimeContext> debugResolveWorkContext(
    AppSession session, {
    String? memberId,
    Workspace? workspace,
  }) =>
      _resolveRoots(session: session, memberId: memberId, workspace: workspace);

  Future<RuntimeContext> _resolveRoots({
    AppSession? session,
    String? memberId,
    Workspace? workspace,
  }) async {
    final workResolver = _workContextResolver;
    if (session != null && workResolver != null) {
      final target = memberId != null
          ? _workTargetForMember(
              WorkspaceLaunchContext(
                session: session,
                workspace:
                    workspace ??
                    Workspace(
                      workspaceId: session.workspaceId,
                      folders: session.folders,
                      createdAt: 0,
                    ),
              ),
              memberId,
            )
          : _workTargetFor(session);
      return workResolver(target);
    }
    final resolver = _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(_appDataBasePath ?? AppStorage.paths.basePath);
  }

  RuntimeTarget _runtimeTargetFromId(String id) =>
      WorkTargetCanonicalizer.resolve(id, home: _homeTarget());

  /// Where the CLI process runs for this launch.
  ///
  /// Personal sessions omit [memberId] and use the workspace session target
  /// (`folders.first.targetId`). Team sessions pin each roster member via
  /// [memberId] → [AppSession.memberTargets].
  RuntimeTarget launchWorkTarget(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) {
    final trimmed = memberId?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return _workTargetForMember(ctx, trimmed);
    }
    return _workTargetFor(ctx.session);
  }

  /// The runtime target of a session's workspace (P2: whole workspace = one
  /// target = `folders.first.targetId`).
  RuntimeTarget _workTargetFor(AppSession session) {
    final id = session.folders.isEmpty
        ? RuntimeTarget.localId
        : session.folders.first.targetId;
    return _runtimeTargetFromId(id);
  }

  Future<RuntimeContext> launchWorkContext(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) => resolveWorkContextForTargetId(
    launchWorkTarget(ctx, memberId: memberId).id,
  );

  /// P3d: resolve the work-plane context for an arbitrary target id, so the
  /// cross-machine artifact service can read on the publisher's machine and
  /// write on the fetcher's machine. Falls back to the control-plane /home
  /// context when no work-plane resolver is wired (single-machine setups).
  Future<RuntimeContext> resolveWorkContextForTargetId(String targetId) {
    final resolver = _workContextResolver;
    if (resolver != null) return resolver(_runtimeTargetFromId(targetId));
    final fallback = _storageRootsResolver;
    if (fallback != null) return fallback();
    return Future.value(
      _localRoots(_appDataBasePath ?? AppStorage.paths.basePath),
    );
  }

  RuntimeTarget _workTargetForMember(
    WorkspaceLaunchContext ctx,
    String memberId,
  ) {
    final targetId = memberTargetForInstanceId(
      ctx.session.memberTargets,
      memberId,
    );
    if (targetId != null &&
        folderPathsForTarget(ctx.folderCatalog, targetId).isNotEmpty) {
      return _runtimeTargetFromId(targetId);
    }
    final fallback = ctx.folderCatalog.isEmpty ? null : ctx.folderCatalog.first;
    return _runtimeTargetFromId(fallback?.targetId ?? RuntimeTarget.localId);
  }

  bool memberTargetIsValid(WorkspaceLaunchContext ctx, String memberId) {
    final targetId = memberTargetForInstanceId(
      ctx.session.memberTargets,
      memberId,
    );
    if (targetId == null) return false;
    return folderPathsForTarget(ctx.folderCatalog, targetId).isNotEmpty;
  }

  ({String workingDirectory, List<String> addDirs}) memberWorkDirs(
    WorkspaceLaunchContext ctx,
    String memberId,
  ) => ctx.session.workDirsForMember(memberId, folders: ctx.folderCatalog);

  RuntimeContext _localRoots(String basePath) {
    return RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(basePath),
      ),
      home: basePath,
      cwd: basePath,
      appDataRoot: basePath,
      paths: AppPaths(basePath),
    );
  }

  /// Resolves the native session id for [cli] via its [SessionResumeCapability]
  /// (probe / scan / persisted / out-of-band allocate), then derives the
  /// create-vs-resume ids for the launch plan. See
  /// docs/session-resume-architecture.md.
  Future<_ResumeResolution> _resolveResume({
    required RuntimeContext roots,
    required CliTool? cli,
    required String taskId,
    required Map<String, String> env,
    required List<String> transcriptRoots,
    required String bucket,
    required String? persistedNativeId,
    required bool previouslyLaunched,
    String? workspaceId,
    String? sessionId,
    String? memberId,
    String? teamId,
  }) async {
    final cap = cli == null
        ? null
        : _cliToolRegistry.capability<SessionResumeCapability>(cli);
    if (cap == null || cli == null) return const _ResumeResolution();

    final ctx = ResumeContext(
      fs: roots.fs,
      toolValue: cli.value,
      taskId: taskId,
      env: env,
      transcriptRoots: transcriptRoots,
      bucket: bucket,
      persistedNativeId: persistedNativeId,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      teamId: teamId,
      manifestDataRoot: roots.appDataRoot,
    );

    String? nativeId;
    // postCaptured CLIs (cursor/codex/opencode) mint ids into a per-session
    // isolated store. Always probe that store: a stale launchState=created on
    // the in-memory tab must not skip --resume when chats already exist.
    // clientPinned / transcript probes stay gated so a fresh launch does not
    // latch onto shared global transcript roots.
    final shouldDetect =
        previouslyLaunched ||
        (persistedNativeId?.trim().isNotEmpty ?? false) ||
        cap.binding == ResumeBinding.postCaptured;
    if (shouldDetect) {
      nativeId = (await cap.detectNativeId(ctx))?.trim();
      if (nativeId != null && nativeId.isEmpty) nativeId = null;
    }

    final pinned = cap.binding == ResumeBinding.clientPinned;
    if (nativeId != null) {
      return _ResumeResolution(
        resumeSessionId: nativeId,
        // clientPinned native id == taskId; nothing extra to persist.
        nativeSessionIdToPersist: pinned ? null : nativeId,
      );
    }
    // Fresh launch: clientPinned pins our id; others let the CLI mint one.
    return _ResumeResolution(createSessionId: pinned ? taskId : null);
  }

  Future<_CliStateProbeResult> _findCliState({
    required RuntimeContext roots,
    required AppSession session,
    required String teamId,
    required String runtimeSessionId,
    required String cliSessionId,
    CliTool? cli,
    String? workspaceId,
  }) async {
    final id = cliSessionId.trim();
    if (id.isEmpty) {
      return const _CliStateProbeResult(exists: false);
    }

    final tools = cli != null ? [cli.value] : runtimeLayoutDefaultTools;
    final trimmedWorkspaceId = workspaceId?.trim() ?? '';
    final toolRoots = trimmedWorkspaceId.isNotEmpty
        ? _standaloneTranscriptSearchRoots(
            layout: roots.layout,
            workspaceId: trimmedWorkspaceId,
            sessionId: runtimeSessionId,
            tools: tools,
          )
        : roots.layout.transcriptSearchRoots(
            workspaceId: session.workspaceId.trim(),
            sessionId: session.sessionId.trim(),
            profileId: teamId,
            tools: tools,
          );
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
      session.firstFolderPath,
    );
    return _findCliStateInFilesystem(
      fs: roots.fs,
      toolRoots: toolRoots,
      sessionId: id,
      bucket: bucket,
    );
  }

  Future<_CliStateProbeResult> _findCliStateInFilesystem({
    required Filesystem fs,
    required Iterable<String> toolRoots,
    required String sessionId,
    required String bucket,
  }) async {
    final probe = await probePinnedTranscript(
      fs: fs,
      toolRoots: toolRoots,
      sessionId: sessionId,
      bucket: bucket,
      // Claude uses `projects/`; flashskyai uses `workspaces/`.
      layoutSegments: const ['projects', 'workspaces'],
    );
    if (!probe.exists) {
      return const _CliStateProbeResult(exists: false);
    }
    return _CliStateProbeResult(
      exists: true,
      rootsTried: toolRoots.toList(growable: false),
      matchedPath: probe.matchedPath,
    );
  }

  List<CliPreset> get _globalPresets => _loadPresets?.call() ?? const [];

  CliTool _memberLaunchCli(
    TeamProfile team,
    TeamMemberConfig member, {
    AppSession? session,
  }) => sessionMemberLaunchCli(
    session: session,
    team: team,
    member: member,
    globalPresets: _globalPresets,
  );

  Future<void> _removeTree(RuntimeContext roots, String path) async {
    try {
      await roots.fs.removeRecursive(path);
    } on Object catch (e, st) {
      appLogger.w('[session-lifecycle] cleanup failed: $e', stackTrace: st);
    }
  }

  String _memberConfigDirFromEnv(Map<String, String> env) {
    final home = env['HOME']?.trim() ?? '';
    if (home.isNotEmpty) return home;
    return env['CLAUDE_CONFIG_DIR'] ??
        env[FlashskyaiConfigProfileCapability.configDirEnvKey] ??
        env[FlashskyaiConfigProfileCapability.sessionHomeDirEnvKey] ??
        env['CODEX_HOME'] ??
        '';
  }
}

class _PreparedLaunch {
  const _PreparedLaunch({required this.env, this.warnings = const []});

  final Map<String, String> env;
  final List<String> warnings;
}

class _CliStateProbeResult {
  const _CliStateProbeResult({
    required this.exists,
    this.rootsTried = const [],
    this.matchedPath,
  });

  final bool exists;
  final List<String> rootsTried;
  final String? matchedPath;
}

/// Outcome of [SessionLifecycleService._resolveResume]: the ids to pin (create)
/// or replay (resume), plus any native id to persist onto the binding.
class _ResumeResolution {
  const _ResumeResolution({
    this.createSessionId,
    this.resumeSessionId,
    this.nativeSessionIdToPersist,
  });

  final String? createSessionId;
  final String? resumeSessionId;
  final String? nativeSessionIdToPersist;
}

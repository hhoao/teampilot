import 'package:flutter/foundation.dart';

import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/personal_profile.dart';
import '../../models/session_member_binding.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../models/launch_profile.dart';
import '../../repositories/cli_presets_repository.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../utils/team_member_naming.dart';
import '../../utils/workspace_path_utils.dart';
import '../../utils/logger.dart';
import '../../models/workspace_topology.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/capabilities/session_resume_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import '../cli/preset_resolver.dart';
import '../provider/control_plane_profile_paths.dart';
import '../provider/config_profile_service.dart';
import '../../models/runtime_target.dart';
import '../io/local_filesystem.dart';
import '../storage/runtime_context.dart';
import '../io/filesystem.dart';
import '../cli/cli_tool_adapter.dart';
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
    String? Function()? llmConfigPathOverride,
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
  }) : _appDataBasePath = appDataBasePath,
       _llmConfigPathOverride = llmConfigPathOverride,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _workContextResolver = workContextResolver,
       _catalogContextResolver = catalogContextResolver,
       _loadEnabledExtensionIds = loadEnabledExtensionIds,
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry,
       _identityRepository = identityRepository,
       _loadInstalledSkills = loadInstalledSkills,
       _cliPresetsRepository = cliPresetsRepository,
       _loadPresets = loadPresets;

  final String? _appDataBasePath;
  final String? Function()? _llmConfigPathOverride;
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

  /// Global CLI presets used by [resolveMemberLaunchConfig] and launch validation.
  List<CliPreset> get globalPresets => _loadPresets?.call() ?? const [];

  /// Resolves the active [CliPreset] for a personal workspace profile.
  /// Returns `null` when no preset is active or the repository is unavailable.
  Future<CliPreset?> resolveActivePresetForPersonal(
    PersonalProfile personal,
  ) async {
    final repo = _cliPresetsRepository;
    if (repo == null) return null;
    final presets = await repo.load();
    return resolveActivePreset(personal.activePresetId, presets);
  }

  Future<CliPreset?> _resolvePersonalPreset(
    AppSession session,
    PersonalProfile personal,
  ) async {
    final repo = _cliPresetsRepository;
    if (repo == null) return null;
    final presets = await repo.load();
    final active = resolveActivePreset(personal.activePresetId, presets);
    final pinnedCli = session.cli;
    if (pinnedCli == null || active?.cli == pinnedCli) return active;
    for (final preset in presets) {
      if (preset.cli == pinnedCli) return preset;
    }
    return null;
  }

  Future<PersonalProfile> loadPersonalProfile(
    String profileId, {
    PersonalProfile? override,
  }) async {
    if (override != null) return override;
    final trimmed = profileId.trim();
    final repo = _identityRepository;
    PersonalProfile? defaultPersonal;
    if (repo != null) {
      final all = await repo.loadAll();
      for (final identity in all) {
        if (identity is! PersonalProfile) continue;
        if (identity.id == trimmed) return identity;
        if (identity.id == LaunchProfileProvisioner.defaultPersonalId) {
          defaultPersonal = identity;
        }
      }
    }
    // Unknown / dangling id (e.g. the identity was deleted after the session
    // launched): fall back to the default personal identity *with its bundle*
    // rather than a synthetic empty one.
    if (defaultPersonal != null) return defaultPersonal;
    return PersonalProfile(
      id: trimmed.isEmpty
          ? LaunchProfileProvisioner.defaultPersonalId
          : trimmed,
      display: trimmed.isEmpty ? 'Personal' : trimmed,
    );
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
    TeamProfile? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    PersonalProfile? personal,
    String? profileId,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    return (await _prepareLaunchPlan(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      personal: personal,
      profileId: profileId,
      llmConfigPathOverride: llmConfigPathOverride,
      extraMcpServers: extraMcpServers,
      busIdleUrl: busIdleUrl,
    )).plan;
  }

  Future<ShellLaunchSpec> prepareShellLaunch({
    required AppSession session,
    TeamProfile? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    PersonalProfile? personal,
    String? profileId,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    final prepared = await _prepareLaunchPlan(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      personal: personal,
      profileId: profileId,
      llmConfigPathOverride: llmConfigPathOverride,
      extraMcpServers: extraMcpServers,
      busIdleUrl: busIdleUrl,
    );

    return ShellLaunchSpec(
      plan: prepared.plan,
      launchContext: _buildShellLaunchContext(
        session: session,
        plan: prepared.plan,
        isPersonal: prepared.isPersonal,
        workspace: workspace,
        personal: prepared.resolvedPersonal,
        team: team,
        member: prepared.resolvedMember ?? member,
        preset: prepared.activePreset,
      ),
      sessionTeam: _resolveSessionTeam(
        session,
        prepared.plan,
        prepared.isPersonal,
      ),
    );
  }

  TeamMemberConfig? _resolveTeamMemberForLaunch(
    TeamProfile team,
    TeamMemberConfig member,
  ) {
    final presets = _loadPresets?.call() ?? [];
    final resolved = resolveMemberLaunchConfig(
      team: team,
      member: member,
      globalPresets: presets,
    );
    return member.copyWith(
      provider: resolved.provider,
      model: resolved.model,
      effort: resolved.effort,
      updateEffort: true,
    );
  }

  Future<
    ({
      LaunchPlan plan,
      bool isPersonal,
      PersonalProfile? resolvedPersonal,
      CliPreset? activePreset,
      TeamMemberConfig? resolvedMember,
    })
  >
  _prepareLaunchPlan({
    required AppSession session,
    TeamProfile? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    PersonalProfile? personal,
    String? profileId,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    final sessionId = session.sessionId.trim();
    final teamId = (team?.id ?? session.sessionTeam).trim();
    final memberName = member?.name.trim() ?? '';
    final cliTeamName = session.cliTeamName.trim();
    final taskId = memberBinding?.taskId.trim() ?? sessionId;
    final isPersonal = await _resolveIsPersonal(
      session: session,
      workspace: workspace,
      profileId: profileId,
    );
    // P3a: the member runs in its assigned working directory (default = session
    // first folder). Personal sessions have no roster member → inherit.
    final memberWork = session.workDirsForMember(
      isPersonal ? null : memberBinding?.rosterMemberId,
    );
    TeamMemberConfig? launchMember = member;
    if (!isPersonal && team != null && member != null) {
      launchMember = _resolveTeamMemberForLaunch(team, member);
    }
    final personalIdentityId = await _resolvePersonalProfileId(
      profileId: profileId,
      isPersonal: isPersonal,
    );
    appLogger.i(
      '[session-lifecycle] prepareLaunch start '
      'session=$sessionId team=$teamId member=$memberName '
      'cliTeam=$cliTeamName task=$taskId personal=$isPersonal',
    );
    try {
      final roots = await _resolveRoots(
        session: session,
        memberId: isPersonal ? null : memberBinding?.rosterMemberId,
      );
      final service = await _configProfileServiceFor(
        roots,
        launchWorkspaceId: isPersonal ? workspace!.workspaceId : null,
      );
      final resolvedPersonal = isPersonal
          ? await loadPersonalProfile(personalIdentityId, override: personal)
          : null;

      CliPreset? activePreset;
      if (isPersonal && resolvedPersonal != null) {
        activePreset = await _resolvePersonalPreset(session, resolvedPersonal);
      }

      final runtimeTeamId = isPersonal
          ? sessionId
          : (cliTeamName.isNotEmpty ? cliTeamName : sessionId);
      // Mixed members run as isolated processes under per-member CONFIG_DIRs, so
      // transcripts / --resume probes must target the same nested runtime dir.
      final runtimeSessionId = isPersonal
          ? sessionId
          : team?.teamMode == TeamMode.mixed &&
                launchMember != null &&
                launchMember.isValid
          ? mixedModeMemberScopeSessionId(
              roots.fs.pathContext,
              runtimeTeamId,
              launchMember,
            )
          : runtimeTeamId;
      // Mixed-mode members run (and store transcripts) under their own
      // `member.cliWithin(team)` override, which can differ from `team.cli`
      // (the latter defaults to claude when the team JSON omits `cli`).
      // Probe the member's effective CLI so `--resume` finds the prior
      // transcript instead of falling back to `--session-id` (which the running
      // CLI rejects as "Session ID … is already in use").
      final cli = isPersonal
          ? (session.cli ?? activePreset?.cli ?? CliTool.claude)
          : (team != null && launchMember != null && launchMember.isValid
                ? launchMember.cliWithin(team)
                : team?.cli);
      final tools = cli != null ? [cli.value] : runtimeLayoutDefaultTools;
      final transcriptRoots = isPersonal
          ? _standaloneTranscriptSearchRoots(
              layout: roots.layout,
              workspaceId: workspace!.workspaceId,
              sessionId: runtimeSessionId,
              tools: tools,
            )
          : roots.layout.transcriptSearchRoots(
              workspaceId: session.workspaceId.trim(),
              sessionId: session.sessionId.trim(),
              profileId: teamId,
              tools: tools,
            );

      // Env must be prepared first: postCaptured/preAllocated resume strategies
      // need the isolated config dir it establishes (CODEX_HOME / OPENCODE_DATA_DIR
      // / CURSOR_CONFIG_DIR). See docs/session-resume-architecture.md.
      final prepared = await _prepareEnv(
        service: service,
        session: session,
        team: team,
        member: launchMember,
        memberBinding: memberBinding,
        workspace: workspace,
        personal: resolvedPersonal,
        isPersonal: isPersonal,
        runtimeTeamId: runtimeTeamId,
        workingDirectory: memberWork.workingDirectory,
        llmConfigPathOverride: llmConfigPathOverride,
        extraMcpServers: extraMcpServers,
        busIdleUrl: busIdleUrl,
        preset: activePreset,
      );
      final memberConfigDir = _memberConfigDirFromEnv(prepared.env);
      // Mixed members store transcripts under their isolated CONFIG_DIR
      // (`runtime/{memberId}/{tool}`), which is not in [transcriptRoots] until
      // launch env is prepared.
      final rootsForResume = <String>{
        ...transcriptRoots,
        if (memberConfigDir.isNotEmpty) memberConfigDir,
      }.toList(growable: false);

      final resume = await _resolveResume(
        roots: roots,
        cli: cli,
        taskId: taskId,
        env: prepared.env,
        transcriptRoots: rootsForResume,
        bucket: RuntimeLayout.workspaceBucketForPrimaryPath(
          memberWork.workingDirectory,
        ),
        persistedNativeId: cli == null
            ? null
            : (isPersonal
                  ? session.nativeSessionIds[cli.value]
                  : memberBinding?.nativeSessionIds[cli.value]),
        previouslyLaunched:
            session.launchState == AppSessionLaunchState.started,
      );

      final resolvedRoots = rootsForResume;

      final plan = LaunchPlan(
        env: prepared.env,
        resume: resume.resumeSessionId != null,
        taskId: taskId,
        createSessionId: resume.createSessionId,
        resumeSessionId: resume.resumeSessionId,
        nativeSessionIdToPersist: resume.nativeSessionIdToPersist,
        isFreshConversation: resume.isFreshConversation,
        toolValue: cli?.value,
        cliTeamName: runtimeTeamId,
        memberConfigDir: memberConfigDir,
        resolvedRoots: resolvedRoots,
        warnings: prepared.warnings,
      );
      appLogger.i(
        '[session-lifecycle] prepareShellLaunch ready '
        'session=$sessionId resume=${plan.resume} '
        'warnings=${plan.warnings.length}',
      );
      return (
        plan: plan,
        isPersonal: isPersonal,
        resolvedPersonal: resolvedPersonal,
        activePreset: activePreset,
        resolvedMember: launchMember,
      );
    } on Object catch (e, st) {
      appLogger.e(
        '[session-lifecycle] prepareShellLaunch failed '
        'session=$sessionId team=$teamId member=$memberName: $e',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<bool> hasCliState(
    AppSession session, {
    String? teamId,
    CliTool? cli,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    PersonalProfile? personal,
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
      final preset = personal != null
          ? await _resolvePersonalPreset(session, personal)
          : null;
      resolvedCli = session.cli ?? preset?.cli ?? CliTool.claude;
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

  Future<bool> _resolveIsPersonal({
    required AppSession session,
    Workspace? workspace,
    String? profileId,
  }) async {
    final trimmed = profileId?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final identity = await loadIdentity(trimmed);
      if (identity != null) {
        return identity.kind == LaunchProfileKind.personal;
      }
      if (trimmed == LaunchProfileProvisioner.defaultPersonalId) {
        return true;
      }
    }
    return _isPersonalLaunch(workspace, session);
  }

  Future<String> _resolvePersonalProfileId({
    String? profileId,
    required bool isPersonal,
  }) async {
    if (!isPersonal) return LaunchProfileProvisioner.defaultPersonalId;
    final trimmed = profileId?.trim() ?? '';
    if (trimmed.isEmpty) return LaunchProfileProvisioner.defaultPersonalId;
    final identity = await loadIdentity(trimmed);
    if (identity is PersonalProfile) return identity.id;
    if (trimmed == LaunchProfileProvisioner.defaultPersonalId) {
      return LaunchProfileProvisioner.defaultPersonalId;
    }
    return trimmed;
  }

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

  CliLaunchContext _buildShellLaunchContext({
    required AppSession session,
    required LaunchPlan plan,
    required bool isPersonal,
    Workspace? workspace,
    PersonalProfile? personal,
    TeamProfile? team,
    TeamMemberConfig? member,
    CliPreset? preset,
  }) {
    if (isPersonal) {
      if (workspace == null || personal == null) {
        throw StateError(
          'prepareShellLaunch requires workspace and personal identity for personal sessions',
        );
      }
      final launchMember = standaloneMemberFromPersonal(
        personal,
        preset: preset,
      );
      final launchTeam = standaloneTeamFromPersonal(
        personal,
        profileId: personal.id,
        sessionTeamName: plan.cliTeamName,
        preset: preset,
      );
      return CliLaunchContext(
        team: launchTeam,
        member: launchMember,
        sessionTeam: plan.cliTeamName,
        workingDirectory: session.firstFolderPath,
        additionalDirectories: session.extraFolderPaths,
        isFreshConversation: plan.isFreshConversation,
      );
    }

    if (team == null || member == null) {
      throw StateError(
        'prepareShellLaunch requires team and member for team sessions',
      );
    }

    final memberDirs = session.workDirsForMember(member.id);
    return CliLaunchContext(
      team: team,
      member: member,
      sessionTeam: _resolveSessionTeam(session, plan, false),
      workingDirectory: memberDirs.workingDirectory.isNotEmpty
          ? memberDirs.workingDirectory
          : session.firstFolderPath,
      additionalDirectories: memberDirs.addDirs,
      isFreshConversation: plan.isFreshConversation,
    );
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

  Future<_PreparedLaunch> _prepareEnv({
    required ConfigProfileService service,
    required AppSession session,
    required TeamProfile? team,
    required TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    PersonalProfile? personal,
    required bool isPersonal,
    required String runtimeTeamId,
    required String workingDirectory,
    required String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
    CliPreset? preset,
  }) async {
    if (isPersonal) {
      final personalWorkspace = workspace!;
      final resolvedPersonal =
          personal ??
          await loadPersonalProfile(LaunchProfileProvisioner.defaultPersonalId);
      final outcome = await service.prepareWorkspaceLaunch(
        workspaceId: personalWorkspace.workspaceId,
        sessionId: session.sessionId,
        profileId: resolvedPersonal.id,
        personal: resolvedPersonal,
        workingDirectory: workingDirectory,
        additionalDirectories: session.extraFolderPaths,
        extraMcpServers: extraMcpServers,
        busIdleUrl: busIdleUrl,
        preset: preset,
      );
      return _PreparedLaunch(
        env: outcome.environment,
        warnings: outcome.warnings,
      );
    }

    final teamId = team?.id.trim() ?? '';
    if (team != null && teamId.isNotEmpty) {
      final launchCli = member != null ? member.cliWithin(team) : team.cli;
      final leadTaskId = memberBinding?.taskId.trim() ?? '';
      final leadSessionId =
          member != null &&
              TeamMemberNaming.isTeamLead(member) &&
              leadTaskId.isNotEmpty
          ? leadTaskId
          : null;
      final memberDirs = member != null
          ? session.workDirsForMember(
              memberBinding?.rosterMemberId ?? member.id,
            )
          : (
              workingDirectory: session.firstFolderPath,
              addDirs: session.extraFolderPaths,
            );
      final outcome = await service.prepareTeamLaunch(
        workspaceId: effectiveLaunchWorkspaceId(
          workspaceId: session.workspaceId,
          teamId: teamId,
        ),
        sessionId: session.sessionId.trim(),
        teamId: teamId,
        cliTeamName: runtimeTeamId,
        cli: launchCli,
        members: team.members,
        member: member,
        workingDirectory: memberDirs.workingDirectory.isNotEmpty
            ? memberDirs.workingDirectory
            : workingDirectory,
        additionalDirectories: memberDirs.addDirs,
        team: team,
        leadSessionId: leadSessionId,
        extraMcpServers: extraMcpServers,
        busIdleUrl: busIdleUrl,
      );
      return _PreparedLaunch(
        env: outcome.environment,
        warnings: outcome.warnings,
      );
    }

    final override =
        llmConfigPathOverride?.trim() ??
        _llmConfigPathOverride?.call()?.trim() ??
        '';
    if (override.isEmpty) return const _PreparedLaunch(env: {});
    return _PreparedLaunch(env: {'LLM_CONFIG_PATH': override});
  }

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
  }) => _resolveRoots(session: session, memberId: memberId);

  /// Resolves the context for launch. When [session] is given and a work-plane
  /// resolver is wired, the folder target decides the machine — per-member
  /// (P3a, via [memberId]) or whole-session (P2); otherwise the control-plane
  /// /home context is used.
  Future<RuntimeContext> _resolveRoots({
    AppSession? session,
    String? memberId,
  }) async {
    final workResolver = _workContextResolver;
    if (session != null && workResolver != null) {
      final target = memberId != null
          ? _workTargetForMember(session, memberId)
          : _workTargetFor(session);
      return workResolver(target);
    }
    final resolver = _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(_appDataBasePath ?? AppStorage.paths.basePath);
  }

  RuntimeTarget _runtimeTargetFromId(String id) =>
      switch (runtimeKindOfId(id)) {
        RuntimeKind.ssh => RuntimeTarget.ssh(
          sshProfileIdOfId(id) ?? '',
          label: '',
        ),
        RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
        RuntimeKind.local => RuntimeTarget.local(),
      };

  /// The runtime target of a session's workspace (P2: whole workspace = one
  /// target = `folders.first.targetId`).
  RuntimeTarget _workTargetFor(AppSession session) {
    final id = session.folders.isEmpty
        ? RuntimeTarget.localId
        : session.folders.first.targetId;
    return _runtimeTargetFromId(id);
  }

  /// P3a: a member's work target (the machine it runs on). Public seam for the
  /// launch path's remote-bus wiring (#1). One agent, one machine.
  RuntimeTarget memberWorkTarget(AppSession session, String memberId) =>
      _workTargetForMember(session, memberId);

  /// Work-plane storage for a member (ssh/wsl/local), for config inspection and
  /// other per-machine reads that must not use the control-plane /home context.
  Future<RuntimeContext> memberWorkContext(
    AppSession session,
    String memberId,
  ) =>
      resolveWorkContextForTargetId(memberWorkTarget(session, memberId).id);

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

  /// P3a: a member's work target — the targetId of its first assigned folder
  /// (default = the workspace's first folder). One agent, one machine.
  RuntimeTarget _workTargetForMember(AppSession session, String memberId) {
    final assigned = folderAssignmentForMemberId(
      session.folderAssignments,
      memberId,
    );
    if (assigned != null && assigned.isNotEmpty) {
      final targetId = targetIdForFolderPaths(session.folders, assigned);
      if (targetId != null) {
        return _runtimeTargetFromId(targetId);
      }
      final folder = _workspaceFolderForAssignedPaths(session.folders, assigned);
      if (folder != null) {
        return _runtimeTargetFromId(folder.targetId);
      }
      // Do not fall back to session.folders.first — in mixed workspaces that
      // pins the wrong machine while memberWorkDirs still uses assigned paths.
    }
    final fallback = session.folders.isEmpty ? null : session.folders.first;
    return _runtimeTargetFromId(fallback?.targetId ?? RuntimeTarget.localId);
  }

  /// Resolves a workspace folder for member-assigned paths (exact match, then
  /// longest workspace root prefix).
  WorkspaceFolder? _workspaceFolderForAssignedPaths(
    List<WorkspaceFolder> folders,
    List<String> paths,
  ) {
    for (final path in paths) {
      for (final folder in folders) {
        if (workspacePathsEqual(folder.path, path)) return folder;
      }
    }
    for (final path in paths) {
      final normalized = normalizeWorkspacePath(path);
      if (normalized.isEmpty) continue;
      WorkspaceFolder? best;
      var bestRootLen = -1;
      for (final folder in folders) {
        final root = normalizeWorkspacePath(folder.path);
        if (root.isEmpty) continue;
        if (normalized == root || normalized.startsWith('$root/')) {
          if (root.length > bestRootLen) {
            best = folder;
            bestRootLen = root.length;
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// P3a: a member's working directory (assigned first, default session first)
  /// and `--add-dir` directories (assigned rest, default session extras).
  ({String workingDirectory, List<String> addDirs}) memberWorkDirs(
    AppSession session,
    String memberId,
  ) => session.workDirsForMember(memberId);

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
    );

    String? nativeId;
    if (previouslyLaunched || (persistedNativeId?.trim().isNotEmpty ?? false)) {
      nativeId = (await cap.detectNativeId(ctx))?.trim();
      if (nativeId != null && nativeId.isEmpty) nativeId = null;
    }

    final pinned = cap.binding == ResumeBinding.clientPinned;
    if (nativeId != null) {
      return _ResumeResolution(
        resumeSessionId: nativeId,
        // clientPinned native id == taskId; nothing extra to persist.
        nativeSessionIdToPersist: pinned ? null : nativeId,
        isFreshConversation: false,
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
    this.isFreshConversation = true,
  });

  final String? createSessionId;
  final String? resumeSessionId;
  final String? nativeSessionIdToPersist;

  /// Whether this launch starts a conversation with no prior history. Drives
  /// one-time identity seeding for CLIs that inject identity as the opening
  /// prompt (cursor).
  final bool isFreshConversation;
}

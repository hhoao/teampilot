import 'package:flutter/foundation.dart';

import '../../models/workspace.dart';
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
import '../cli/registry/config_profile/config_profile_context.dart';
import '../../utils/team_member_naming.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/capabilities/session_resume_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import '../cli/preset_resolver.dart';
import '../provider/config_profile_service.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';
import '../storage/runtime_storage_context.dart';
import '../cli/cli_tool_adapter.dart';
import 'shell_launch_spec.dart';

export 'shell_launch_spec.dart';

typedef StorageRootsResolver = Future<StorageRootsSnapshot> Function();

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
      id: trimmed.isEmpty ? LaunchProfileProvisioner.defaultPersonalId : trimmed,
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

    // Resolve preset for team sessions so the CLI launches with the
    // preset's provider/model/effort rather than the member's raw fields.
    TeamMemberConfig? resolvedMember = member;
    if (!prepared.isPersonal && team != null && member != null) {
      final presets = _loadPresets?.call() ?? [];
      final resolved = resolveMemberLaunchConfig(
        team: team,
        member: member,
        globalPresets: presets,
      );
      resolvedMember = member.copyWith(
        provider: resolved.provider,
        model: resolved.model,
        effort: resolved.effort,
        updateEffort: true,
      );
    }

    return ShellLaunchSpec(
      plan: prepared.plan,
      launchContext: _buildShellLaunchContext(
        session: session,
        plan: prepared.plan,
        isPersonal: prepared.isPersonal,
        workspace: workspace,
        personal: prepared.resolvedPersonal,
        team: team,
        member: resolvedMember,
        preset: prepared.activePreset,
      ),
      sessionTeam: _resolveSessionTeam(
        session,
        prepared.plan,
        prepared.isPersonal,
      ),
    );
  }

  Future<
    ({
      LaunchPlan plan,
      bool isPersonal,
      PersonalProfile? resolvedPersonal,
      CliPreset? activePreset,
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
      final roots = await _resolveRoots();
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
          : team?.teamMode == TeamMode.mixed && member != null && member.isValid
          ? mixedModeMemberScopeSessionId(
              roots.fs.pathContext,
              runtimeTeamId,
              member,
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
          : (team != null && member != null && member.isValid
                ? member.cliWithin(team)
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
        member: member,
        memberBinding: memberBinding,
        workspace: workspace,
        personal: resolvedPersonal,
        isPersonal: isPersonal,
        runtimeTeamId: runtimeTeamId,
        workingDirectory: session.primaryPath,
        llmConfigPathOverride: llmConfigPathOverride,
        extraMcpServers: extraMcpServers,
        busIdleUrl: busIdleUrl,
        preset: activePreset,
      );
      final memberConfigDir = _memberConfigDirFromEnv(prepared.env);

      final resume = await _resolveResume(
        roots: roots,
        cli: cli,
        taskId: taskId,
        env: prepared.env,
        transcriptRoots: transcriptRoots,
        bucket: RuntimeLayout.workspaceBucketForPrimaryPath(session.primaryPath),
        persistedNativeId: cli == null
            ? null
            : (isPersonal
                  ? session.nativeSessionIds[cli.value]
                  : memberBinding?.nativeSessionIds[cli.value]),
        previouslyLaunched:
            session.launchState == AppSessionLaunchState.started,
      );

      final resolvedRoots = <String>{
        ...transcriptRoots,
        if (memberConfigDir.isNotEmpty) memberConfigDir,
      }.toList(growable: false);

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
    final roots = await _resolveRoots();
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
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedSessionId.isEmpty) {
      return;
    }

    final roots = await _resolveRoots();
    final sessionRoot = roots.layout.workspace.sessionRuntimeDir(
      trimmedWorkspaceId,
      trimmedSessionId,
    );
    await _removeTree(roots, sessionRoot);
  }

  Future<void> destroyStandaloneCliState({
    required String workspaceId,
    required String sessionId,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) return;

    final roots = await _resolveRoots();
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
      final launchMember =
          standaloneMemberFromPersonal(personal, preset: preset);
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
        workingDirectory: session.primaryPath,
        additionalDirectories: session.additionalPaths,
        isFreshConversation: plan.isFreshConversation,
      );
    }

    if (team == null || member == null) {
      throw StateError(
        'prepareShellLaunch requires team and member for team sessions',
      );
    }

    return CliLaunchContext(
      team: team,
      member: member,
      sessionTeam: _resolveSessionTeam(session, plan, false),
      workingDirectory: session.primaryPath,
      additionalDirectories: session.additionalPaths,
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
      final resolvedPersonal = personal ??
          await loadPersonalProfile(LaunchProfileProvisioner.defaultPersonalId);
      final outcome = await service.prepareWorkspaceLaunch(
        workspaceId: personalWorkspace.workspaceId,
        sessionId: session.sessionId,
        profileId: resolvedPersonal.id,
        personal: resolvedPersonal,
        workingDirectory: workingDirectory,
        additionalDirectories: session.additionalPaths,
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
        workingDirectory: workingDirectory,
        additionalDirectories: session.additionalPaths,
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
    StorageRootsSnapshot roots, {
    String? launchWorkspaceId,
  }) async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    final loader = _loadEnabledExtensionIds;
    final trimmedWorkspaceId = launchWorkspaceId?.trim() ?? '';
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      fs: roots.fs,
      layout: roots.layout,
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

  Future<StorageRootsSnapshot> _resolveRoots() async {
    final resolver = _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(_appDataBasePath ?? AppStorage.paths.basePath);
  }

  StorageRootsSnapshot _localRoots(String basePath) {
    return StorageRootsSnapshot.fromContext(RuntimeStorageContext.current);
  }

  /// Resolves the native session id for [cli] via its [SessionResumeCapability]
  /// (probe / scan / persisted / out-of-band allocate), then derives the
  /// create-vs-resume ids for the launch plan. See
  /// docs/session-resume-architecture.md.
  Future<_ResumeResolution> _resolveResume({
    required StorageRootsSnapshot roots,
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
    required StorageRootsSnapshot roots,
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
      session.primaryPath,
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

  Future<void> _removeTree(StorageRootsSnapshot roots, String path) async {
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

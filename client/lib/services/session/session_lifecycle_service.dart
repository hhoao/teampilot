import 'package:flutter/foundation.dart';

import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/identity_kind.dart';
import '../../models/personal_identity.dart';
import '../../models/session_member_binding.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../models/workspace_identity.dart';
import '../../repositories/cli_presets_repository.dart';
import '../../repositories/identity_repository.dart';
import '../../services/storage/identity_provisioner.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../../utils/team_member_naming.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
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
    Future<Set<String>> Function({String? teamId, String? projectId})?
    loadEnabledExtensionIds,
    CliToolRegistry? cliToolRegistry,
    IdentityRepository? identityRepository,
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
  final Future<Set<String>> Function({String? teamId, String? projectId})?
  _loadEnabledExtensionIds;
  final CliToolRegistry _cliToolRegistry;
  final IdentityRepository? _identityRepository;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  final CliPresetsRepository? _cliPresetsRepository;
  final List<CliPreset> Function()? _loadPresets;

  /// Resolves the active [CliPreset] for a personal project profile.
  /// Returns `null` when no preset is active or the repository is unavailable.
  Future<CliPreset?> resolveActivePresetForPersonal(
    PersonalIdentity personal,
  ) async {
    final repo = _cliPresetsRepository;
    if (repo == null) return null;
    final presets = await repo.load();
    return resolveActivePreset(personal.activePresetId, presets);
  }

  Future<CliPreset?> _resolvePersonalPreset(
    AppSession session,
    PersonalIdentity personal,
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

  Future<PersonalIdentity> loadPersonalIdentity(
    String identityId, {
    PersonalIdentity? override,
  }) async {
    if (override != null) return override;
    final trimmed = identityId.trim();
    final repo = _identityRepository;
    PersonalIdentity? defaultPersonal;
    if (repo != null) {
      final all = await repo.loadAll();
      for (final identity in all) {
        if (identity is! PersonalIdentity) continue;
        if (identity.id == trimmed) return identity;
        if (identity.id == IdentityProvisioner.defaultPersonalId) {
          defaultPersonal = identity;
        }
      }
    }
    // Unknown / dangling id (e.g. the identity was deleted after the session
    // launched): fall back to the default personal identity *with its bundle*
    // rather than a synthetic empty one.
    if (defaultPersonal != null) return defaultPersonal;
    return PersonalIdentity(
      id: trimmed.isEmpty ? IdentityProvisioner.defaultPersonalId : trimmed,
      display: trimmed.isEmpty ? 'Personal' : trimmed,
    );
  }

  Future<Identity?> loadIdentity(String identityId) async {
    final trimmed = identityId.trim();
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
    TeamIdentity? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    PersonalIdentity? personal,
    String? identityId,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    return (await _prepareLaunchPlan(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      project: project,
      personal: personal,
      identityId: identityId,
      llmConfigPathOverride: llmConfigPathOverride,
      extraMcpServers: extraMcpServers,
      busIdleUrl: busIdleUrl,
    )).plan;
  }

  Future<ShellLaunchSpec> prepareShellLaunch({
    required AppSession session,
    TeamIdentity? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    PersonalIdentity? personal,
    String? identityId,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    final prepared = await _prepareLaunchPlan(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      project: project,
      personal: personal,
      identityId: identityId,
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
        project: project,
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
      PersonalIdentity? resolvedPersonal,
      CliPreset? activePreset,
    })
  >
  _prepareLaunchPlan({
    required AppSession session,
    TeamIdentity? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    PersonalIdentity? personal,
    String? identityId,
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
      project: project,
      identityId: identityId,
    );
    final personalIdentityId = await _resolvePersonalIdentityId(
      identityId: identityId,
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
        launchProjectId: isPersonal ? project!.projectId : null,
      );
      final resolvedPersonal = isPersonal
          ? await loadPersonalIdentity(personalIdentityId, override: personal)
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
              projectId: project!.projectId,
              sessionId: runtimeSessionId,
              tools: tools,
            )
          : roots.layout.transcriptSearchRoots(
              projectId: session.projectId.trim(),
              sessionId: session.sessionId.trim(),
              identityId: teamId,
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
        project: project,
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
        bucket: RuntimeLayout.projectBucketForPrimaryPath(session.primaryPath),
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
    AppProject? project,
    PersonalIdentity? personal,
  }) async {
    final roots = await _resolveRoots();
    final isPersonal = _isPersonalLaunch(project, session);
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
      projectId: isPersonal ? project!.projectId : null,
    );
    return probe.exists;
  }

  Future<void> destroyCliState({
    required String projectId,
    required String teamId,
    required String sessionId,
  }) async {
    final trimmedProjectId = projectId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedProjectId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedSessionId.isEmpty) {
      return;
    }

    final roots = await _resolveRoots();
    final sessionRoot = roots.layout.workspace.sessionRuntimeDir(
      trimmedProjectId,
      trimmedSessionId,
    );
    await _removeTree(roots, sessionRoot);
  }

  Future<void> destroyStandaloneCliState({
    required String projectId,
    required String sessionId,
  }) async {
    final trimmedProjectId = projectId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedProjectId.isEmpty || trimmedSessionId.isEmpty) return;

    final roots = await _resolveRoots();
    final sessionRoot = roots.layout.workspace.sessionRuntimeDir(
      trimmedProjectId,
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

  bool _isPersonalLaunch(AppProject? project, AppSession session) =>
      project != null && session.sessionTeam.trim().isEmpty;

  Future<bool> _resolveIsPersonal({
    required AppSession session,
    AppProject? project,
    String? identityId,
  }) async {
    final trimmed = identityId?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final identity = await loadIdentity(trimmed);
      if (identity != null) {
        return identity.kind == IdentityKind.personal;
      }
      if (trimmed == IdentityProvisioner.defaultPersonalId) {
        return true;
      }
    }
    return _isPersonalLaunch(project, session);
  }

  Future<String> _resolvePersonalIdentityId({
    String? identityId,
    required bool isPersonal,
  }) async {
    if (!isPersonal) return IdentityProvisioner.defaultPersonalId;
    final trimmed = identityId?.trim() ?? '';
    if (trimmed.isEmpty) return IdentityProvisioner.defaultPersonalId;
    final identity = await loadIdentity(trimmed);
    if (identity is PersonalIdentity) return identity.id;
    if (trimmed == IdentityProvisioner.defaultPersonalId) {
      return IdentityProvisioner.defaultPersonalId;
    }
    return trimmed;
  }

  /// Test-only seam for [_isPersonalLaunch].
  @visibleForTesting
  bool debugIsPersonalLaunch(AppProject project, AppSession session) =>
      _isPersonalLaunch(project, session);

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
    AppProject? project,
    PersonalIdentity? personal,
    TeamIdentity? team,
    TeamMemberConfig? member,
    CliPreset? preset,
  }) {
    if (isPersonal) {
      if (project == null || personal == null) {
        throw StateError(
          'prepareShellLaunch requires project and personal identity for personal sessions',
        );
      }
      final launchMember =
          standaloneMemberFromPersonal(personal, preset: preset);
      final launchTeam = standaloneTeamFromPersonal(
        personal,
        identityId: personal.id,
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
    required String projectId,
    required String sessionId,
    required Iterable<String> tools,
  }) {
    final tt = tools.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [
      for (final tool in tt) layout.appToolRoot(tool),
      for (final tool in tt) layout.projectConfigToolDir(projectId, tool),
      for (final tool in tt)
        layout.sessionRuntimeToolDir(projectId, sessionId, tool),
    ];
  }

  Future<_PreparedLaunch> _prepareEnv({
    required ConfigProfileService service,
    required AppSession session,
    required TeamIdentity? team,
    required TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    PersonalIdentity? personal,
    required bool isPersonal,
    required String runtimeTeamId,
    required String workingDirectory,
    required String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
    CliPreset? preset,
  }) async {
    if (isPersonal) {
      final personalProject = project!;
      final resolvedPersonal = personal ??
          await loadPersonalIdentity(IdentityProvisioner.defaultPersonalId);
      final outcome = await service.prepareProjectLaunch(
        projectId: personalProject.projectId,
        sessionId: session.sessionId,
        identityId: resolvedPersonal.id,
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
        projectId: effectiveLaunchProjectId(
          projectId: session.projectId,
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
    String? launchProjectId,
  }) async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    final loader = _loadEnabledExtensionIds;
    final trimmedProjectId = launchProjectId?.trim() ?? '';
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      fs: roots.fs,
      layout: roots.layout,
      loadEnabledExtensionIds: loader == null
          ? null
          : ({teamId, projectId}) => loader(
              teamId: teamId,
              projectId: (projectId?.trim().isNotEmpty ?? false)
                  ? projectId
                  : (trimmedProjectId.isNotEmpty ? trimmedProjectId : null),
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
    String? projectId,
  }) async {
    final id = cliSessionId.trim();
    if (id.isEmpty) {
      return const _CliStateProbeResult(exists: false);
    }

    final tools = cli != null ? [cli.value] : runtimeLayoutDefaultTools;
    final trimmedProjectId = projectId?.trim() ?? '';
    final toolRoots = trimmedProjectId.isNotEmpty
        ? _standaloneTranscriptSearchRoots(
            layout: roots.layout,
            projectId: trimmedProjectId,
            sessionId: runtimeSessionId,
            tools: tools,
          )
        : roots.layout.transcriptSearchRoots(
            projectId: session.projectId.trim(),
            sessionId: session.sessionId.trim(),
            identityId: teamId,
            tools: tools,
          );
    final bucket = RuntimeLayout.projectBucketForPrimaryPath(
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
    final path = fs.pathContext;
    final memberSegment = '${path.separator}members${path.separator}';
    final orderedRoots = [
      for (final root in toolRoots)
        if (root.contains(memberSegment)) root,
      for (final root in toolRoots)
        if (!root.contains(memberSegment)) root,
    ];
    final rootsTried = <String>[];
    for (final root in orderedRoots) {
      rootsTried.add(root);
      final projectsDir = path.join(root, 'projects');
      if (bucket.isNotEmpty) {
        final bucketDir = path.join(projectsDir, bucket);
        final transcriptFile = path.join(bucketDir, '$sessionId.jsonl');
        if ((await fs.stat(transcriptFile)).isFile) {
          return _CliStateProbeResult(
            exists: true,
            rootsTried: rootsTried,
            matchedPath: transcriptFile,
          );
        }
        final transcriptDir = path.join(bucketDir, sessionId);
        if ((await fs.stat(transcriptDir)).isDirectory) {
          return _CliStateProbeResult(
            exists: true,
            rootsTried: rootsTried,
            matchedPath: transcriptDir,
          );
        }
      }
      final scanned = await _scanProjects(fs, projectsDir, sessionId);
      if (scanned != null) {
        return _CliStateProbeResult(
          exists: true,
          rootsTried: rootsTried,
          matchedPath: scanned,
        );
      }
    }
    return _CliStateProbeResult(exists: false, rootsTried: rootsTried);
  }

  static Future<String?> _scanProjects(
    Filesystem fs,
    String projectsDir,
    String sessionId,
  ) async {
    final path = fs.pathContext;
    try {
      final buckets = await fs.listDir(projectsDir);
      for (final bucket in buckets) {
        if (!bucket.isDirectory) continue;
        final bucketPath = path.join(projectsDir, bucket.name);
        final transcriptFile = path.join(bucketPath, '$sessionId.jsonl');
        if ((await fs.stat(transcriptFile)).isFile) return transcriptFile;
        final transcriptDir = path.join(bucketPath, sessionId);
        if ((await fs.stat(transcriptDir)).isDirectory) return transcriptDir;
      }
    } on Object {
      return null;
    }
    return null;
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

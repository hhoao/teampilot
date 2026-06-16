import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/project_profile.dart';
import '../../models/session_member_binding.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../repositories/cli_presets_repository.dart';
import '../../repositories/project_profile_repository.dart';
import '../../utils/team_member_naming.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import '../cli/registry/capabilities/transcript_probe_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/config_profile/config_profile_scope.dart';
import '../cli/registry/config_profile/flashskyai_config_profile_capability.dart';
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
    ProjectProfileRepository? projectProfileRepository,
    Future<List<Skill>> Function()? loadInstalledSkills,
    CliPresetsRepository? cliPresetsRepository,
  }) : _appDataBasePath = appDataBasePath,
       _llmConfigPathOverride = llmConfigPathOverride,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _loadEnabledExtensionIds = loadEnabledExtensionIds,
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry,
       _projectProfileRepository = projectProfileRepository,
       _loadInstalledSkills = loadInstalledSkills,
       _cliPresetsRepository = cliPresetsRepository;

  final String? _appDataBasePath;
  final String? Function()? _llmConfigPathOverride;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final Future<Set<String>> Function({String? teamId, String? projectId})?
  _loadEnabledExtensionIds;
  final CliToolRegistry _cliToolRegistry;
  final ProjectProfileRepository? _projectProfileRepository;
  final Future<List<Skill>> Function()? _loadInstalledSkills;
  final CliPresetsRepository? _cliPresetsRepository;

  Future<ProjectProfile> loadProjectProfile(
    String projectId, {
    ProjectProfile? override,
  }) async {
    if (override != null) return override;
    final repo = _projectProfileRepository;
    if (repo != null) {
      return repo.loadOrCreate(projectId);
    }
    return ProjectProfile(projectId: projectId);
  }

  Future<LaunchPlan> prepareLaunch({
    required AppSession session,
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    ProjectProfile? profile,
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
      profile: profile,
      llmConfigPathOverride: llmConfigPathOverride,
      extraMcpServers: extraMcpServers,
      busIdleUrl: busIdleUrl,
    )).plan;
  }

  Future<ShellLaunchSpec> prepareShellLaunch({
    required AppSession session,
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    ProjectProfile? profile,
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
      profile: profile,
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
        project: project,
        profile: prepared.resolvedProfile,
        team: team,
        member: member,
        preset: prepared.activePreset,
      ),
      sessionTeam: _resolveSessionTeam(session, prepared.plan, prepared.isPersonal),
    );
  }

  Future<({
    LaunchPlan plan,
    bool isPersonal,
    ProjectProfile? resolvedProfile,
    CliPreset? activePreset,
  })> _prepareLaunchPlan({
    required AppSession session,
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    ProjectProfile? profile,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    final sessionId = session.sessionId.trim();
    final teamId = (team?.id ?? session.sessionTeam).trim();
    final memberName = member?.name.trim() ?? '';
    final cliTeamName = session.cliTeamName.trim();
    final taskId = memberBinding?.taskId.trim() ?? sessionId;
    final isPersonal = _isPersonalLaunch(project, session);
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
      final resolvedProfile = isPersonal
          ? await loadProjectProfile(project!.projectId, override: profile)
          : null;

      // Resolve active preset for personal projects
      CliPreset? activePreset;
      if (isPersonal && resolvedProfile != null) {
        final repo = _cliPresetsRepository;
        if (repo != null) {
          final presets = await repo.load();
          activePreset = resolveActivePreset(
            resolvedProfile.activePresetId,
            presets,
          );
        }
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
          ? (activePreset?.cli ?? CliTool.claude)
          : (team != null && member != null && member.isValid
              ? member.cliWithin(team)
              : team?.cli);
      final cliState = session.launchState == AppSessionLaunchState.started
          ? await _findCliState(
              roots: roots,
              session: session,
              teamId: teamId,
              runtimeSessionId: runtimeSessionId,
              cliSessionId: taskId,
              cli: cli,
              projectId: isPersonal ? project!.projectId : null,
            )
          : _CliStateProbeResult(
              exists: false,
              rootsTried: isPersonal
                  ? _standaloneTranscriptSearchRoots(
                      layout: roots.layout,
                      projectId: project!.projectId,
                      sessionId: runtimeSessionId,
                      tools: cli != null ? [cli.value] : runtimeLayoutDefaultTools,
                    )
                  : roots.layout.transcriptSearchRoots(
                      projectId: session.projectId.trim(),
                      sessionId: session.sessionId.trim(),
                      teamId: teamId,
                      tools: cli != null ? [cli.value] : runtimeLayoutDefaultTools,
                    ),
            );
      final prepared = await _prepareEnv(
        service: service,
        session: session,
        team: team,
        member: member,
        memberBinding: memberBinding,
        project: project,
        profile: resolvedProfile,
        runtimeTeamId: runtimeTeamId,
        workingDirectory: session.primaryPath,
        llmConfigPathOverride: llmConfigPathOverride,
        extraMcpServers: extraMcpServers,
        busIdleUrl: busIdleUrl,
        preset: activePreset,
      );
      final memberConfigDir = _memberConfigDirFromEnv(prepared.env);
      final resolvedRoots = <String>{
        ...cliState.rootsTried,
        if (memberConfigDir.isNotEmpty) memberConfigDir,
      }.toList(growable: false);

      final plan = LaunchPlan(
        env: prepared.env,
        resume: cliState.exists,
        taskId: taskId,
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
        resolvedProfile: resolvedProfile,
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
    ProjectProfile? profile,
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
    if (isPersonal && profile?.activePresetId != null) {
      final repo = _cliPresetsRepository;
      if (repo != null) {
        final presets = await repo.load();
        final activePreset = resolveActivePreset(profile!.activePresetId, presets);
        resolvedCli = activePreset?.cli ?? CliTool.claude;
      } else {
        resolvedCli = CliTool.claude;
      }
    } else {
      resolvedCli = isPersonal ? CliTool.claude : cli;
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
      roots.layout.teamToolDir(trimmedTeamId, 'flashskyai'),
    );
    await _removeTree(roots, teamRoot);
  }

  bool _isPersonalLaunch(AppProject? project, AppSession session) =>
      project != null &&
      project.teamId.isEmpty &&
      session.sessionTeam.trim().isEmpty;

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
    ProjectProfile? profile,
    TeamConfig? team,
    TeamMemberConfig? member,
    CliPreset? preset,
  }) {
    if (isPersonal) {
      if (project == null || profile == null) {
        throw StateError(
          'prepareShellLaunch requires project and profile for personal sessions',
        );
      }
      final launchMember = standaloneMemberFromProfile(profile, preset: preset);
      final launchTeam = standaloneTeamFromProfile(
        profile,
        projectId: project.projectId,
        sessionTeamName: plan.cliTeamName,
        preset: preset,
      );
      return CliLaunchContext(
        team: launchTeam,
        member: launchMember,
        sessionTeam: plan.cliTeamName,
        workingDirectory: session.primaryPath,
        additionalDirectories: session.additionalPaths,
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
    required TeamConfig? team,
    required TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    AppProject? project,
    ProjectProfile? profile,
    required String runtimeTeamId,
    required String workingDirectory,
    required String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
    CliPreset? preset,
  }) async {
    if (_isPersonalLaunch(project, session)) {
      final personalProject = project!;
      final resolvedProfile =
          profile ?? await loadProjectProfile(personalProject.projectId);
      final outcome = await service.prepareProjectLaunch(
        projectId: personalProject.projectId,
        sessionId: session.sessionId,
        profile: resolvedProfile,
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
            teamId: teamId,
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
      probeHistoryFiles:
          (cli == null
                  ? null
                  : _cliToolRegistry.capability<TranscriptProbeCapability>(cli))
              ?.probeHistoryFiles ??
          false,
    );
  }

  Future<_CliStateProbeResult> _findCliStateInFilesystem({
    required Filesystem fs,
    required Iterable<String> toolRoots,
    required String sessionId,
    required String bucket,
    required bool probeHistoryFiles,
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

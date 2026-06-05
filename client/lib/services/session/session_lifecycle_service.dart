import '../../models/app_session.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';
import '../../utils/logger.dart';
import '../storage/app_storage.dart';
import '../cli/cli_data_layout.dart';
import '../cli/registry/built_in_cli_tools.dart';
import '../cli/registry/capabilities/transcript_probe_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import '../provider/config_profile_service.dart';
import '../storage/storage_resolver.dart';
import '../io/filesystem.dart';
import '../storage/runtime_storage_context.dart';

typedef StorageRootsResolver = Future<StorageRootsSnapshot> Function();

class LaunchPlan {
  const LaunchPlan({
    required this.env,
    required this.resume,
    required this.taskId,
    required this.cliTeamName,
    required this.memberConfigDir,
    required this.resolvedRoots,
    this.warnings = const [],
  });

  final Map<String, String> env;
  final bool resume;

  /// CLI `--session-id` / `--resume` id (member [SessionMemberBinding.taskId]).
  final String taskId;

  /// CLI `--team-name` and config-profiles member runtime directory.
  final String cliTeamName;
  final String memberConfigDir;
  final List<String> resolvedRoots;
  final List<String> warnings;
}

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
    Future<Set<String>> Function({String? teamId})? loadEnabledExtensionIds,
    CliToolRegistry? cliToolRegistry,
  }) : _appDataBasePath = appDataBasePath,
       _llmConfigPathOverride = llmConfigPathOverride,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _loadEnabledExtensionIds = loadEnabledExtensionIds,
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry;

  final String? _appDataBasePath;
  final String? Function()? _llmConfigPathOverride;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final Future<Set<String>> Function({String? teamId})?
  _loadEnabledExtensionIds;
  final CliToolRegistry _cliToolRegistry;

  Future<LaunchPlan> prepareLaunch({
    required AppSession session,
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
    final sessionId = session.sessionId.trim();
    final teamId = (team?.id ?? session.sessionTeam).trim();
    final memberName = member?.name.trim() ?? '';
    final cliTeamName = session.cliTeamName.trim();
    final taskId = memberBinding?.taskId.trim() ?? sessionId;
    appLogger.i(
      '[session-lifecycle] prepareLaunch start '
      'session=$sessionId team=$teamId member=$memberName '
      'cliTeam=$cliTeamName task=$taskId',
    );
    try {
      final roots = await _resolveRoots();
      final service = await _configProfileServiceFor(roots);
      final runtimeTeamId = cliTeamName.isNotEmpty ? cliTeamName : sessionId;
      // Mixed members run as isolated processes under per-member CONFIG_DIRs, so
      // transcripts / --resume probes must target the same nested runtime dir.
      final runtimeSessionId =
          team?.teamMode == TeamMode.mixed && member != null && member.isValid
          ? mixedModeMemberScopeSessionId(
              roots.fs.pathContext,
              runtimeTeamId,
              member,
            )
          : runtimeTeamId;
      final cli = team?.cli;
      final cliState = session.launchState == AppSessionLaunchState.started
          ? await _findCliState(
              roots: roots,
              session: session,
              teamId: teamId,
              runtimeSessionId: runtimeSessionId,
              cliSessionId: taskId,
              cli: cli,
            )
          : _CliStateProbeResult(
              exists: false,
              rootsTried: roots.layout.transcriptSearchRoots(
                teamId: teamId,
                runtimeSessionId: runtimeSessionId,
                tools: cli != null ? [cli.value] : cliLayoutDefaultTools,
              ),
            );
      final prepared = await _prepareEnv(
        service: service,
        session: session,
        team: team,
        member: member,
        memberBinding: memberBinding,
        runtimeTeamId: runtimeTeamId,
        workingDirectory: session.primaryPath,
        llmConfigPathOverride: llmConfigPathOverride,
        extraMcpServers: extraMcpServers,
        busIdleUrl: busIdleUrl,
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
        '[session-lifecycle] prepareLaunch ready '
        'session=$sessionId resume=${plan.resume} '
        'warnings=${plan.warnings.length}',
      );
      return plan;
    } on Object catch (e, st) {
      appLogger.e(
        '[session-lifecycle] prepareLaunch failed '
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
  }) async {
    final roots = await _resolveRoots();
    final runtimeTeamId = session.cliTeamName.trim().isNotEmpty
        ? session.cliTeamName.trim()
        : session.sessionId.trim();
    final cliSessionId =
        memberBinding?.taskId.trim() ?? session.sessionId.trim();
    final probe = await _findCliState(
      roots: roots,
      session: session,
      teamId: (teamId ?? session.sessionTeam).trim(),
      runtimeSessionId: runtimeTeamId,
      cliSessionId: cliSessionId,
      cli: cli,
    );
    return probe.exists;
  }

  Future<void> destroyCliState({
    required String teamId,
    required String sessionId,
    String? runtimeSessionId,
  }) async {
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedTeamId.isEmpty || trimmedSessionId.isEmpty) return;
    final runtime = runtimeSessionId?.trim();
    final memberDirectoryId = runtime != null && runtime.isNotEmpty
        ? runtime
        : trimmedSessionId;

    final roots = await _resolveRoots();
    final memberRoot = roots.fs.pathContext.dirname(
      roots.layout.memberToolDir(
        trimmedTeamId,
        memberDirectoryId,
        'flashskyai',
      ),
    );
    await _removeTree(roots, memberRoot);
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

  Future<_PreparedLaunch> _prepareEnv({
    required ConfigProfileService service,
    required AppSession session,
    required TeamConfig? team,
    required TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    required String runtimeTeamId,
    required String workingDirectory,
    required String? llmConfigPathOverride,
    Map<String, Map<String, Object?>>? extraMcpServers,
    String? busIdleUrl,
  }) async {
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
        teamId: teamId,
        runtimeTeamId: runtimeTeamId,
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
    StorageRootsSnapshot roots,
  ) async {
    final injected = _configProfileService;
    if (injected != null) return injected;
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      fs: roots.fs,
      layout: roots.layout,
      loadEnabledExtensionIds: _loadEnabledExtensionIds,
      cliRegistry: _cliToolRegistry,
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
  }) async {
    final id = cliSessionId.trim();
    if (id.isEmpty) {
      return const _CliStateProbeResult(exists: false);
    }

    final toolRoots = roots.layout.transcriptSearchRoots(
      teamId: teamId,
      runtimeSessionId: runtimeSessionId,
      tools: cli != null ? [cli.value] : cliLayoutDefaultTools,
    );
    final bucket = CliDataLayout.projectBucketForPrimaryPath(
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

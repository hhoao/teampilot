import 'dart:convert';

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'claude_provider_settings_resolver.dart';
import 'cli_data_layout.dart';
import 'config_profile_service.dart';
import 'flashskyai_storage_roots.dart';
import 'io/filesystem.dart';
import 'io/local_filesystem.dart';

typedef StorageRootsResolver = Future<StorageRootsSnapshot> Function();

class LaunchPlan {
  const LaunchPlan({
    required this.env,
    required this.resume,
    required this.sessionIdArg,
    required this.memberConfigDir,
    required this.resolvedRoots,
  });

  final Map<String, String> env;
  final bool resume;
  final String sessionIdArg;
  final String memberConfigDir;
  final List<String> resolvedRoots;
}

class SessionLifecycleService {
  SessionLifecycleService({
    String? appDataBasePath,
    String? Function()? llmConfigPathOverride,
    ConfigProfileService? configProfileService,
    StorageRootsResolver? storageRootsResolver,
    ClaudeProviderSettingsResolver? claudeSettingsResolver,
  }) : _appDataBasePath = appDataBasePath,
       _llmConfigPathOverride = llmConfigPathOverride,
       _configProfileService = configProfileService,
       _storageRootsResolver = storageRootsResolver,
       _claudeSettingsResolver = claudeSettingsResolver;

  final String? _appDataBasePath;
  final String? Function()? _llmConfigPathOverride;
  final ConfigProfileService? _configProfileService;
  final StorageRootsResolver? _storageRootsResolver;
  final ClaudeProviderSettingsResolver? _claudeSettingsResolver;

  Future<LaunchPlan> prepareLaunch({
    required AppSession session,
    TeamConfig? team,
    TeamMemberConfig? member,
    String? llmConfigPathOverride,
  }) async {
    final roots = await _resolveRoots();
    final service = await _configProfileServiceFor(roots);
    final sessionId = session.sessionId.trim();
    final teamId = (team?.id ?? session.sessionTeam).trim();
    final runtimeTeamId = session.effectiveCliTeamDirectory;
    final cliState = session.launchState == AppSessionLaunchState.started
        ? await _findCliState(
            roots: roots,
            session: session,
            teamId: teamId,
            runtimeSessionId: runtimeTeamId,
          )
        : _CliStateProbeResult(
            exists: false,
            rootsTried: roots.layout.transcriptSearchRoots(
              teamId: teamId,
              runtimeSessionId: runtimeTeamId,
            ),
          );

    final env = await _prepareEnv(
      service: service,
      team: team,
      member: member,
      runtimeTeamId: runtimeTeamId,
      workingDirectory: session.primaryPath,
      llmConfigPathOverride: llmConfigPathOverride,
    );
    final memberConfigDir = _memberConfigDirFromEnv(env);
    final resolvedRoots = <String>{
      ...cliState.rootsTried,
      if (memberConfigDir.isNotEmpty) memberConfigDir,
    }.toList(growable: false);

    final plan = LaunchPlan(
      env: env,
      resume: cliState.exists,
      sessionIdArg: sessionId,
      memberConfigDir: memberConfigDir,
      resolvedRoots: resolvedRoots,
    );
    _logLaunchPlan(
      session: session,
      team: team,
      plan: plan,
      roots: roots,
      matchedCliStatePath: cliState.matchedPath,
    );
    return plan;
  }

  Future<bool> hasCliState(AppSession session, {String? teamId}) async {
    final roots = await _resolveRoots();
    final probe = await _findCliState(
      roots: roots,
      session: session,
      teamId: (teamId ?? session.sessionTeam).trim(),
      runtimeSessionId: session.effectiveCliTeamDirectory,
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

  Future<void> destroyTeamCliState(String teamId) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) return;

    final roots = await _resolveRoots();
    final teamRoot = roots.fs.pathContext.dirname(
      roots.layout.teamToolDir(trimmedTeamId, 'flashskyai'),
    );
    await _removeTree(roots, teamRoot);
  }

  Future<Map<String, String>> _prepareEnv({
    required ConfigProfileService service,
    required TeamConfig? team,
    required TeamMemberConfig? member,
    required String runtimeTeamId,
    required String workingDirectory,
    required String? llmConfigPathOverride,
  }) async {
    final teamId = team?.id.trim() ?? '';
    if (team != null && teamId.isNotEmpty) {
      final resolver =
          _claudeSettingsResolver ??
          ClaudeProviderSettingsResolver(basePath: service.basePath);
      final claudeSettings = team.cli == TeamCli.claude
          ? await resolver.resolveTeamClaudeSettings(team)
          : null;
      final claudeSettingsByMember = team.cli == TeamCli.claude
          ? await _loadClaudeMemberProviderSettings(
              resolver: resolver,
              team: team,
              teamClaudeSettings: claudeSettings,
              launchedMember: member,
            )
          : const <String, Map<String, Object?>>{};
      return service.prepareTeamLaunch(
        teamId: teamId,
        runtimeTeamId: runtimeTeamId,
        cli: team.cli,
        members: team.members,
        member: member,
        workingDirectory: workingDirectory,
        claudeSettings: claudeSettings,
        claudeSettingsByMember: claudeSettingsByMember,
      );
    }

    final override =
        llmConfigPathOverride?.trim() ??
        _llmConfigPathOverride?.call()?.trim() ??
        '';
    if (override.isEmpty) return const {};
    return {'LLM_CONFIG_PATH': override};
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
    );
  }

  Future<StorageRootsSnapshot> _resolveRoots() async {
    final resolver = _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(
      _appDataBasePath ?? AppPathsBootstrapper.current.basePath,
    );
  }

  StorageRootsSnapshot _localRoots(String basePath) {
    final fs = LocalFilesystem();
    final layout = CliDataLayout(teampilotRoot: basePath, fs: fs);
    return StorageRootsSnapshot(
      teampilotRoot: basePath,
      fs: fs,
      layout: layout,
      teamsUiDir: AppPaths.teamsUiDirForTeampilotRoot(basePath),
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(basePath),
      skillBackupsDir: AppPaths.skillBackupsDirForTeampilotRoot(basePath),
      appProjectsDir: AppPaths.appProjectsDirForTeampilotRoot(basePath),
      skillReposConfigPath: AppPaths.skillReposConfigPathForTeampilotRoot(
        basePath,
      ),
    );
  }

  Future<_CliStateProbeResult> _findCliState({
    required StorageRootsSnapshot roots,
    required AppSession session,
    required String teamId,
    required String runtimeSessionId,
  }) async {
    final id = session.sessionId.trim();
    if (id.isEmpty) {
      return const _CliStateProbeResult(exists: false);
    }

    final toolRoots = roots.layout.transcriptSearchRoots(
      teamId: teamId,
      runtimeSessionId: runtimeSessionId,
    );
    final bucket = CliDataLayout.projectBucketForPrimaryPath(
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
    final rootsTried = <String>[];
    for (final root in toolRoots) {
      rootsTried.add(root);
      final sessionFile = path.join(root, 'sessions', '$sessionId.json');
      if ((await fs.stat(sessionFile)).isFile) {
        return _CliStateProbeResult(
          exists: true,
          rootsTried: rootsTried,
          matchedPath: sessionFile,
        );
      }
      final sessionEnvFile = path.join(root, 'session-env', sessionId);
      if ((await fs.stat(sessionEnvFile)).isDirectory) {
        return _CliStateProbeResult(
          exists: true,
          rootsTried: rootsTried,
          matchedPath: sessionEnvFile,
        );
      }

      final historyFiles = ['history.jsonl', 'history.json'];

      for (final historyFile in historyFiles) {
        final history = path.join(root, historyFile);
        if ((await fs.stat(history)).isFile) {
          final historyText = await fs.readString(history);
          final historyLines = historyText?.split('\n') ?? [];
          for (final line in historyLines) {
            final historyEntry = jsonDecode(line);
            if (historyEntry['sessionId'].toString().trim() == sessionId) {
              return _CliStateProbeResult(
                exists: true,
                rootsTried: rootsTried,
                matchedPath: history,
              );
            }
          }
        }
      }

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

  Future<Map<String, Map<String, Object?>>> _loadClaudeMemberProviderSettings({
    required ClaudeProviderSettingsResolver resolver,
    required TeamConfig team,
    required Map<String, Object?>? teamClaudeSettings,
    required TeamMemberConfig? launchedMember,
  }) async {
    final members = <String, TeamMemberConfig>{};
    for (final member in team.members.where((member) => member.isValid)) {
      members[member.id] = member;
    }
    final selected = launchedMember;
    if (selected != null && selected.isValid) {
      members[selected.id] = selected;
    }

    final settingsByMember = <String, Map<String, Object?>>{};
    for (final member in members.values) {
      final settings = await resolver.resolveMemberClaudeSettings(
        team: team,
        member: member,
        teamClaudeSettings: teamClaudeSettings,
      );
      if (settings != null) {
        settingsByMember[member.id] = settings;
        settingsByMember[member.name] = settings;
      }
    }
    return settingsByMember;
  }

  String _memberConfigDirFromEnv(Map<String, String> env) {
    return env['CLAUDE_CONFIG_DIR'] ??
        env['FLASHSKYAI_CONFIG_DIR'] ??
        env['CODEX_HOME'] ??
        '';
  }

  void _logLaunchPlan({
    required AppSession session,
    required TeamConfig? team,
    required LaunchPlan plan,
    required StorageRootsSnapshot roots,
    required String? matchedCliStatePath,
  }) {
    appLogger.d(
      '[launch] sid=${session.sessionId} team=${team?.id ?? session.sessionTeam} cli=${team?.cli.value ?? 'flashskyai'}\n'
      '  appRoot=${roots.layout.appToolRoot(team?.cli.value ?? 'flashskyai')}\n'
      '  teamRoot=${(team?.id ?? session.sessionTeam).trim().isEmpty ? '' : roots.layout.teamToolDir((team?.id ?? session.sessionTeam).trim(), team?.cli.value ?? 'flashskyai')}\n'
      '  memberRoot=${plan.memberConfigDir}\n'
      '  searched=${plan.resolvedRoots}\n'
      '  resume=${plan.resume}${matchedCliStatePath == null ? '' : ' (matched $matchedCliStatePath)'}\n'
      '  env keys=${plan.env.keys.toList()}',
    );
  }
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

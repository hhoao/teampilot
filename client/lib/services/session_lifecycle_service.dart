import 'dart:convert';

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../utils/team_member_naming.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'claude_provider_settings_resolver.dart';
import 'cli_data_layout.dart';
import 'config_profile_service.dart';
import 'flashskyai_storage_roots.dart';
import 'io/filesystem.dart';
import 'runtime_storage_context.dart';

typedef StorageRootsResolver = Future<StorageRootsSnapshot> Function();

void _logLaunchTiming(String label, int elapsedMs) {
  appLogger.i('[launch-timing] $label: ${elapsedMs}ms');
}

class LaunchPlan {
  const LaunchPlan({
    required this.env,
    required this.resume,
    required this.sessionIdArg,
    required this.memberConfigDir,
    required this.resolvedRoots,
    this.warnings = const [],
  });

  final Map<String, String> env;
  final bool resume;
  final String sessionIdArg;
  final String memberConfigDir;
  final List<String> resolvedRoots;
  final List<String> warnings;
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
    final total = Stopwatch()..start();
    var step = Stopwatch()..start();
    final roots = await _resolveRoots();
    _logLaunchTiming('prepareLaunch.resolveRoots', step.elapsedMilliseconds);
    step = Stopwatch()..start();
    final service = await _configProfileServiceFor(roots);
    _logLaunchTiming(
      'prepareLaunch.configProfileServiceFor',
      step.elapsedMilliseconds,
    );
    final sessionId = session.sessionId.trim();
    final teamId = (team?.id ?? session.sessionTeam).trim();
    final runtimeTeamId = session.effectiveCliTeamDirectory;
    final cli = team?.cli;
    step = Stopwatch()..start();
    final cliState = session.launchState == AppSessionLaunchState.started
        ? await _findCliState(
            roots: roots,
            session: session,
            teamId: teamId,
            runtimeSessionId: runtimeTeamId,
            cli: cli,
          )
        : _CliStateProbeResult(
            exists: false,
            rootsTried: roots.layout.transcriptSearchRoots(
              teamId: teamId,
              runtimeSessionId: runtimeTeamId,
              tools: cli != null ? [cli.value] : cliLayoutDefaultTools,
            ),
          );
    _logLaunchTiming('prepareLaunch.findCliState', step.elapsedMilliseconds);

    step = Stopwatch()..start();
    final prepared = await _prepareEnv(
      service: service,
      session: session,
      team: team,
      member: member,
      runtimeTeamId: runtimeTeamId,
      workingDirectory: session.primaryPath,
      llmConfigPathOverride: llmConfigPathOverride,
    );
    _logLaunchTiming('prepareLaunch.prepareEnv', step.elapsedMilliseconds);
    final memberConfigDir = _memberConfigDirFromEnv(prepared.env);
    final resolvedRoots = <String>{
      ...cliState.rootsTried,
      if (memberConfigDir.isNotEmpty) memberConfigDir,
    }.toList(growable: false);

    final plan = LaunchPlan(
      env: prepared.env,
      resume: cliState.exists,
      sessionIdArg: sessionId,
      memberConfigDir: memberConfigDir,
      resolvedRoots: resolvedRoots,
      warnings: prepared.warnings,
    );
    _logLaunchTiming('prepareLaunch.total', total.elapsedMilliseconds);
    return plan;
  }

  Future<bool> hasCliState(
    AppSession session, {
    String? teamId,
    TeamCli? cli,
  }) async {
    final roots = await _resolveRoots();
    final probe = await _findCliState(
      roots: roots,
      session: session,
      teamId: (teamId ?? session.sessionTeam).trim(),
      runtimeSessionId: session.effectiveCliTeamDirectory,
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

  Future<void> destroyTeamCliState(String teamId) async {
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
    required String runtimeTeamId,
    required String workingDirectory,
    required String? llmConfigPathOverride,
  }) async {
    final total = Stopwatch()..start();
    final teamId = team?.id.trim() ?? '';
    if (team != null && teamId.isNotEmpty) {
      var step = Stopwatch()..start();
      final resolver =
          _claudeSettingsResolver ??
          ClaudeProviderSettingsResolver(basePath: service.basePath);
      final claudeSettings = team.cli == TeamCli.claude
          ? await resolver.resolveTeamClaudeSettings(team)
          : null;
      _logLaunchTiming(
        'prepareEnv.resolveTeamClaudeSettings',
        step.elapsedMilliseconds,
      );
      step = Stopwatch()..start();
      final claudeProviderId = team.cli == TeamCli.claude
          ? await resolver.resolveProviderId(team)
          : null;
      _logLaunchTiming(
        'prepareEnv.resolveProviderId',
        step.elapsedMilliseconds,
      );
      step = Stopwatch()..start();
      final claudeSettingsByMember = team.cli == TeamCli.claude
          ? await _loadClaudeMemberProviderSettings(
              resolver: resolver,
              team: team,
              teamClaudeSettings: claudeSettings,
              launchedMember: member,
            )
          : const <String, Map<String, Object?>>{};
      _logLaunchTiming(
        'prepareEnv.loadClaudeMemberProviderSettings',
        step.elapsedMilliseconds,
      );
      final leadSessionId =
          member?.name == TeamMemberNaming.teamLeadName &&
              session.sessionId.trim().isNotEmpty
          ? session.sessionId.trim()
          : null;
      step = Stopwatch()..start();
      final outcome = await service.prepareTeamLaunch(
        teamId: teamId,
        runtimeTeamId: runtimeTeamId,
        cli: team.cli,
        members: team.members,
        member: member,
        workingDirectory: workingDirectory,
        additionalDirectories: session.additionalPaths,
        claudeSettings: claudeSettings,
        claudeSettingsByMember: claudeSettingsByMember,
        team: team,
        leadSessionId: leadSessionId,
        claudeProviderId: claudeProviderId,
      );
      _logLaunchTiming(
        'prepareEnv.prepareTeamLaunch',
        step.elapsedMilliseconds,
      );
      _logLaunchTiming('prepareEnv.total', total.elapsedMilliseconds);
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
    TeamCli? cli,
  }) async {
    final id = session.sessionId.trim();
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
      probeHistoryFiles: cli == TeamCli.claude,
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
    final rootsTried = <String>[];
    for (final root in toolRoots) {
      rootsTried.add(root);
      // final sessionFile = path.join(root, 'sessions', '$sessionId.json');
      // if ((await fs.stat(sessionFile)).isFile) {
      //   return _CliStateProbeResult(
      //     exists: true,
      //     rootsTried: rootsTried,
      //     matchedPath: sessionFile,
      //   );
      // }
      // final sessionEnvFile = path.join(root, 'session-env', sessionId);
      // if ((await fs.stat(sessionEnvFile)).isDirectory) {
      //   return _CliStateProbeResult(
      //     exists: true,
      //     rootsTried: rootsTried,
      //     matchedPath: sessionEnvFile,
      //   );
      // }

      // if (probeHistoryFiles) {
      //   final historyFiles = ['history.jsonl', 'history.json'];
      //   for (final historyFile in historyFiles) {
      //     final history = path.join(root, historyFile);
      //     if ((await fs.stat(history)).isFile) {
      //       final historyText = await fs.readString(history);
      //       final historyLines = historyText?.split('\n') ?? [];
      //       for (final line in historyLines) {
      //         final historyEntry = jsonDecode(line);
      //         if (historyEntry['sessionId'].toString().trim() == sessionId) {
      //           return _CliStateProbeResult(
      //             exists: true,
      //             rootsTried: rootsTried,
      //             matchedPath: history,
      //           );
      //         }
      //       }
      //     }
      //   }
      // }

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
        env[ConfigProfileService.flashskyaiConfigDirEnvKey] ??
        env[ConfigProfileService.flashskyaiSessionHomeDirEnvKey] ??
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

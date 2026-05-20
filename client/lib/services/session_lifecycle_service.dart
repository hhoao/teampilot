import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'claude_provider_settings_resolver.dart';
import 'cli_data_layout.dart';
import 'config_profile_service.dart';
import 'flashskyai_storage_roots.dart';
import 'remote_file_store.dart';

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
    final memberRoot = p.dirname(
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
    final teamRoot = p.dirname(
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
    final remote = roots.remoteFileStore;
    return ConfigProfileService(
      basePath: roots.teampilotRoot,
      createDirectory: roots.storageIsRemote && remote != null
          ? remote.ensureDirectory
          : null,
      layout: roots.layout,
    );
  }

  Future<StorageRootsSnapshot> _resolveRoots() async {
    final resolver = _storageRootsResolver;
    if (resolver != null) return resolver();
    return _localRoots(_appDataBasePath ?? AppStorage.basePath);
  }

  StorageRootsSnapshot _localRoots(String basePath) {
    return StorageRootsSnapshot(
      storageIsRemote: false,
      teampilotRoot: basePath,
      teamsUiDir: AppStorage.teamsUiDirForTeampilotRoot(basePath),
      skillsRoot: AppStorage.skillsDirForTeampilotRoot(basePath),
      skillBackupsDir: AppStorage.skillBackupsDirForTeampilotRoot(basePath),
      appProjectsDir: AppStorage.appProjectsDirForTeampilotRoot(basePath),
      skillReposConfigPath: AppStorage.skillReposConfigPathForTeampilotRoot(
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
    final remote = roots.remoteFileStore;
    if (roots.storageIsRemote && remote != null) {
      return _findRemoteCliState(
        store: remote,
        toolRoots: toolRoots,
        sessionId: id,
        bucket: bucket,
      );
    }
    return _findLocalCliState(
      toolRoots: toolRoots,
      sessionId: id,
      bucket: bucket,
    );
  }

  _CliStateProbeResult _findLocalCliState({
    required Iterable<String> toolRoots,
    required String sessionId,
    required String bucket,
  }) {
    final rootsTried = <String>[];
    for (final root in toolRoots) {
      rootsTried.add(root);
      final sessionFile = p.join(root, 'sessions', '$sessionId.json');
      if (File(sessionFile).existsSync()) {
        return _CliStateProbeResult(
          exists: true,
          rootsTried: rootsTried,
          matchedPath: sessionFile,
        );
      }
      final projectsDir = p.join(root, 'projects');
      if (bucket.isNotEmpty) {
        final bucketDir = p.join(projectsDir, bucket);
        final transcriptFile = p.join(bucketDir, '$sessionId.jsonl');
        if (File(transcriptFile).existsSync()) {
          return _CliStateProbeResult(
            exists: true,
            rootsTried: rootsTried,
            matchedPath: transcriptFile,
          );
        }
        final transcriptDir = p.join(bucketDir, sessionId);
        if (Directory(transcriptDir).existsSync()) {
          return _CliStateProbeResult(
            exists: true,
            rootsTried: rootsTried,
            matchedPath: transcriptDir,
          );
        }
      }
      final scanned = _scanProjectsLocal(projectsDir, sessionId);
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

  Future<_CliStateProbeResult> _findRemoteCliState({
    required RemoteFileStore store,
    required Iterable<String> toolRoots,
    required String sessionId,
    required String bucket,
  }) async {
    final posix = p.Context(style: p.Style.posix);
    final rootsTried = <String>[];
    for (final root in toolRoots) {
      rootsTried.add(root);
      final sessionFile = posix.join(root, 'sessions', '$sessionId.json');
      if (await store.fileExists(sessionFile)) {
        return _CliStateProbeResult(
          exists: true,
          rootsTried: rootsTried,
          matchedPath: sessionFile,
        );
      }
      final projectsDir = posix.join(root, 'projects');
      if (bucket.isNotEmpty) {
        final bucketDir = posix.join(projectsDir, bucket);
        final transcriptFile = posix.join(bucketDir, '$sessionId.jsonl');
        if (await store.fileExists(transcriptFile)) {
          return _CliStateProbeResult(
            exists: true,
            rootsTried: rootsTried,
            matchedPath: transcriptFile,
          );
        }
        try {
          final entries = await store.listDirectoryEntries(bucketDir);
          if (entries.any((e) => e.isDirectory && e.name == sessionId)) {
            return _CliStateProbeResult(
              exists: true,
              rootsTried: rootsTried,
              matchedPath: posix.join(bucketDir, sessionId),
            );
          }
        } on Object {
          // Fall through to broad scan.
        }
      }
      final scanned = await _scanProjectsRemote(store, projectsDir, sessionId);
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

  static String? _scanProjectsLocal(String projectsDir, String sessionId) {
    final root = Directory(projectsDir);
    if (!root.existsSync()) return null;
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final bucketPath = entity.path;
        final transcriptFile = p.join(bucketPath, '$sessionId.jsonl');
        if (File(transcriptFile).existsSync()) return transcriptFile;
        final transcriptDir = p.join(bucketPath, sessionId);
        if (Directory(transcriptDir).existsSync()) return transcriptDir;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  static Future<String?> _scanProjectsRemote(
    RemoteFileStore store,
    String projectsDir,
    String sessionId,
  ) async {
    final posix = p.Context(style: p.Style.posix);
    try {
      final buckets = await store.listDirectoryEntries(projectsDir);
      for (final bucket in buckets) {
        if (!bucket.isDirectory) continue;
        final bucketPath = posix.join(projectsDir, bucket.name);
        final transcriptFile = posix.join(bucketPath, '$sessionId.jsonl');
        if (await store.fileExists(transcriptFile)) return transcriptFile;
        try {
          final inner = await store.listDirectoryEntries(bucketPath);
          if (inner.any((e) => e.isDirectory && e.name == sessionId)) {
            return posix.join(bucketPath, sessionId);
          }
        } on Object {
          continue;
        }
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<void> _removeTree(StorageRootsSnapshot roots, String path) async {
    final remote = roots.remoteFileStore;
    if (roots.storageIsRemote && remote != null) {
      try {
        await remote.removeRecursive(path);
      } on Object catch (e, st) {
        appLogger.w(
          '[session-lifecycle] remote cleanup failed: $e',
          stackTrace: st,
        );
      }
      return;
    }

    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
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

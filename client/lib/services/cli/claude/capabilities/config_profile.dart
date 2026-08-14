import 'dart:convert';

import '../../../../models/team_config.dart';
import 'provider.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../team_roster_service.dart';

final class ClaudeConfigProfileCapability implements ConfigProfileCapability {
  const ClaudeConfigProfileCapability();

  static const toolId = 'claude';
  static const metadataFileName = '.claude.json';
  static const settingsFileEnvKey = 'TEAMPILOT_CLAUDE_SETTINGS_FILE';

  /// MCP 工具调用超时(毫秒)。team-bus 的 `wait_for_message` 是长阻塞工具,
  /// claude 默认的工具超时会在几分钟后掐断它(progress notification 不续命,
  /// 见 MCP SDK `resetTimeoutOnProgress` 默认 false)。设大到 24h 让 claude 不
  /// 主动超时,对齐 codex 的 `tool_timeout_sec`(那边单位是秒:86400)。
  static const busToolTimeoutMs = 86400000; // 24h，单位 ms

  static const defaultMetadata = <String, Object?>{
    'hasCompletedOnboarding': true,
    // Follow the embedded terminal's light/dark instead of Claude's built-in
    // 'dark' default, so a session is themed out of the box (no `/theme`). The
    // CLI resolves 'auto' from the COLORFGBG we inject at launch
    // (see PtyLaunchEnvironment.applyColorScheme). Seed-only: a later user
    // `/theme` choice is written to the file and wins via `{...defaults, ...existing}`.
    'theme': 'auto',
  };

  static const defaultProjectConfig = <String, Object?>{
    'hasTrustDialogAccepted': true,
    'hasCompletedProjectOnboarding': true,
    'projectOnboardingSeenCount': 1,
    'hasClaudeMdExternalIncludesApproved': true,
    'hasClaudeMdExternalIncludesWarningShown': true,
    'allowedTools': <Object?>[],
    'mcpServers': <String, Object?>{},
  };

  /// Matches Claude Code `normalizeApiKeyForConfig` (last 20 chars).
  static String normalizeCustomApiKeySuffix(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 20) return trimmed;
    return trimmed.substring(trimmed.length - 20);
  }

  static Map<String, Object?> mergeApprovedCustomApiKeyMetadata(
    Map<String, Object?> metadata,
    String apiKey,
  ) {
    final suffix = normalizeCustomApiKeySuffix(apiKey);
    if (suffix.isEmpty) return metadata;

    final responses = Map<String, Object?>.from(
      (metadata['customApiKeyResponses'] as Map?)?.cast<String, Object?>() ??
          const {},
    );
    final approved = List<Object?>.from(
      (responses['approved'] as List?) ?? const <Object?>[],
    );
    if (!approved.contains(suffix)) {
      approved.add(suffix);
    }
    responses['approved'] = approved;
    responses.putIfAbsent('rejected', () => <Object?>[]);

    return {...metadata, 'customApiKeyResponses': responses};
  }

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {
    await _ensureSessionDefaults(
      ctx.paths,
      ctx.workspaceId,
      ctx.sessionId,
      memberId: ctx.memberId,
    );
  }

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final delegate = ctx.paths;
    final workingDirectory = ctx.workingDirectory ?? '';
    final team = ctx.team;
    final simple = ctx.isSimple;
    final warnings = <String>[];
    final mixed = team?.teamMode == TeamMode.mixed;

    await _provisionWorkspaceTrust(
      delegate: delegate,
      workspaceId: ctx.scope.workspaceId,
      workingDirectory: workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );

    final contribution = await const ClaudeProviderCapability()
        .materializeSessionHome(
          sessionHomeContextFromLaunch(ctx, CliTool.claude),
        );
    warnings.addAll(contribution.warnings);

    final teammateMode = ClaudeProviderCapability.resolveTeammateMode(
      team,
      mixed: mixed,
      simple: simple,
    );
    if (!mixed && !simple) {
      await _writeRoster(
        delegate: delegate,
        scope: ctx.scope,
        members: ctx.members,
        workingDirectory: workingDirectory,
        description: team?.description ?? '',
        leadSessionId: ctx.leadSessionId,
        teammateMode: teammateMode,
      );
    }

    final member = ctx.member;
    final environment = <String, String>{
      ...contribution.environment,
      if (member != null && member.isValid)
        settingsFileEnvKey: ClaudeProviderCapability.sessionMemberSettingsFile(
          delegate,
          ctx.scope.workspaceId,
          ctx.scope.sessionId,
          member,
          memberId: ctx.scope.memberId,
        ),
      if (!mixed && !simple) 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      'CLAUDE_CODE_NO_FLICKER': '1',
      'MCP_TOOL_TIMEOUT': '$busToolTimeoutMs',
    };

    return ConfigProfileLaunchContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  Future<void> _ensureSessionDefaults(
    ConfigProfileDelegate delegate,
    String workspaceId,
    String sessionId, {
    String? memberId,
  }) async {
    await _ensureSessionDefaultsAt(
      delegate,
      delegate.sessionToolDir(
        workspaceId,
        sessionId,
        toolId,
        memberId: memberId,
      ),
    );
  }

  Future<void> _ensureSessionDefaultsAt(
    ConfigProfileDelegate delegate,
    String memberToolDir,
  ) async {
    final file = delegate.joinWork(memberToolDir, metadataFileName);
    final existing = await delegate.readMetadataFile(file, defaultMetadata);
    await delegate.writeJsonIfChanged(file, {...defaultMetadata, ...existing});
  }

  Future<void> _writeRoster({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required List<TeamMemberConfig> members,
    required String workingDirectory,
    required String description,
    required String teammateMode,
    String? leadSessionId,
  }) async {
    final claudeDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final rosterDir = delegate.joinWork(
      claudeDir,
      'teams',
      ClaudeTeamRosterService.safeClaudePathSegment(scope.cliTeamName),
    );
    final rosterPath = delegate.joinWork(rosterDir, 'config.json');

    final cwd = ClaudeTeamRosterService.resolveWorkingDirectory(
      workingDirectory: workingDirectory,
      fallback: '',
    );

    Map<String, Object?>? existing;
    if ((await delegate.fs.stat(rosterPath)).exists) {
      final raw = await delegate.fs.readString(rosterPath);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          existing = Map<String, Object?>.from(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    }

    final rosterService = ClaudeTeamRosterService(fs: delegate.fs);
    final config = rosterService.mergeConfig(
      cliTeamName: scope.cliTeamName,
      members: members,
      cwd: cwd,
      teammateMode: teammateMode,
      description: description,
      leadSessionId: leadSessionId,
      existing: existing,
    );

    await delegate.fs.atomicWrite(
      rosterPath,
      const JsonEncoder.withIndent('  ').convert(config),
    );
    await rosterService.ensureInboxes(rosterDir: rosterDir, members: members);
  }

  Future<void> _provisionWorkspaceTrust({
    required ConfigProfileDelegate delegate,
    required String workspaceId,
    required String workingDirectory,
    List<String> additionalDirectories = const [],
  }) {
    return WorkspaceTrustProvisioner(
      layout: delegate.layout,
      fs: delegate.fs,
    ).provisionWorkspace(
      workspaceId: workspaceId,
      directories: [
        if (workingDirectory.trim().isNotEmpty) workingDirectory.trim(),
        for (final directory in additionalDirectories)
          if (directory.trim().isNotEmpty) directory.trim(),
      ],
      tools: const [ClaudeConfigProfileCapability.toolId],
    );
  }
}

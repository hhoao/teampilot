import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../models/claude_credential_link_result.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/team_member_naming.dart';
import '../../../provider/claude_official_provider.dart';
import '../../../provider/claude_provider_settings_resolver.dart';
import '../../../provider/config_profile_service.dart';
import '../../../session/member_role_provision.dart';
import '../../../team/claude_team_roster_service.dart';
import '../capabilities/config_profile_capability.dart';
import '../config_profile/config_profile_context.dart';

/// mixed：往成员 settings 的 hooks.Stop 加一个 http 通知（成员 idle → POST /idle）。
@visibleForTesting
Map<String, Object?> mergeStopIdleHook(
  Map<String, Object?> settings,
  String memberId,
  String idleUrl,
) {
  final hooks = Map<String, Object?>.from(
    (settings['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  final stop = List<Object?>.from((hooks['Stop'] as List?) ?? const []);
  final exists = stop.any(
    (e) =>
        e is Map &&
        (e['hooks'] as List?)?.any(
              (h) => h is Map && h['url'] == idleUrl,
            ) ==
            true,
  );
  if (!exists) {
    stop.add({
      'hooks': [
        {
          'type': 'http',
          'url': idleUrl,
          'headers': {'X-Member': memberId},
        },
      ],
    });
  }
  hooks['Stop'] = stop;
  return {...settings, 'hooks': hooks};
}

final class ClaudeConfigProfileCapability implements ConfigProfileCapability {
  const ClaudeConfigProfileCapability();

  static const metadataFileName = '.claude.json';

  Future<ClaudeLaunchExtras> resolveLaunchExtras({
    required TeamConfig team,
    required TeamMemberConfig? member,
    required ClaudeProviderSettingsResolver resolver,
  }) async {
    final settings = await resolver.resolveTeamClaudeSettings(team);
    final providerId = await resolver.resolveProviderId(team);
    final settingsByMember = await _loadMemberProviderSettings(
      resolver: resolver,
      team: team,
      teamClaudeSettings: settings,
      launchedMember: member,
    );
    return ClaudeLaunchExtras(
      settings: settings,
      providerId: providerId,
      settingsByMember: settingsByMember,
    );
  }

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {
    await _ensureSessionDefaults(ctx.paths, ctx.teamId, ctx.sessionId);
  }

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final delegate = ctx.paths;
    final scope = ctx.scope;
    final workingDirectory = ctx.workingDirectory ?? '';
    final claude = ctx.claude;
    final warnings = <String>[];
    final mixed = ctx.team?.teamMode == TeamMode.mixed;

    await _writeMetadata(
      delegate,
      scope,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    await _writeSettings(
      delegate,
      scope,
      claude?.settings,
      effortLevel: ctx.team?.claudeEffortLevel ?? 'xhigh',
      teammateMode: ctx.team?.claudeTeammateMode ?? 'in-process',
    );
    if (!mixed) {
      await _writeRoster(
        delegate: delegate,
        scope: scope,
        members: ctx.members,
        workingDirectory: workingDirectory,
        description: ctx.team?.description ?? '',
        leadSessionId: ctx.leadSessionId,
        teammateMode: ctx.team?.claudeTeammateMode ?? 'in-process',
      );
    }
    await _writeMemberProfiles(
      delegate: delegate,
      scope: scope,
      members: ctx.members,
      launchedMember: ctx.member,
      providerSettings: claude?.settings,
      providerSettingsByMember: claude?.settingsByMember ?? const {},
      forceTeamLeadDelegateMode: ctx.team?.forceTeamLeadDelegateMode ?? false,
      mixed: ctx.team?.teamMode == TeamMode.mixed,
      idleUrl: ctx.busIdleUrl,
    );

    final providerId = claude?.providerId?.trim() ?? '';
    if (providerId.isNotEmpty &&
        claude?.settings != null &&
        isOfficialClaudeSettings(claude!.settings!)) {
      final sessionClaudeDir = delegate.sessionToolDir(
        scope.teamId,
        scope.sessionId,
        'claude',
      );
      final link = await delegate.claudeCredentials.ensureLinked(
        sessionClaudeDir,
        providerId,
      );
      if (link == CredentialLinkResult.missing) {
        warnings.add('claude_credentials_missing');
      }
    }

    final member = ctx.member;
    final environment = <String, String>{
      'CLAUDE_CONFIG_DIR': delegate.sessionToolDir(
        scope.teamId,
        scope.sessionId,
        'claude',
      ),
      if (member != null && member.isValid)
        ConfigProfileService.claudeSettingsFileEnvKey:
            delegate.sessionClaudeMemberSettingsFile(
          scope.teamId,
          scope.sessionId,
          member,
        ),
      if (!mixed) 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      'CLAUDE_CODE_NO_FLICKER': '1',
    };

    if (member != null && member.isValid) {
      final appendPath = await delegate.resolveAppendSystemPromptPath(
        scope: scope,
        tool: 'claude',
        member: member,
      );
      if (appendPath != null) {
        environment[MemberRoleProvision.appendSystemPromptFileEnvKey] =
            appendPath;
      }
    }

    return ConfigProfileLaunchContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  Future<void> _ensureSessionDefaults(
    ConfigProfileDelegate delegate,
    String teamId,
    String sessionId,
  ) async {
    final file = delegate.sessionClaudeMetadataFile(teamId, sessionId);
    final existing = await delegate.readMetadataFile(
      file,
      ConfigProfileService.defaultClaudeMetadata,
    );
    await delegate.writeJsonIfChanged(file, {
      ...ConfigProfileService.defaultClaudeMetadata,
      ...existing,
    });
  }

  Future<void> _writeSettings(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
  }) async {
    final file = delegate.pathContext.join(
      delegate.sessionToolDir(scope.teamId, scope.sessionId, 'claude'),
      'settings.json',
    );
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: delegate.sessionToolDir(
        scope.teamId,
        scope.sessionId,
        'claude',
      ),
    );
  }

  Future<void> _writeMetadata(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = delegate.sessionClaudeMetadataFile(
      scope.teamId,
      scope.sessionId,
    );
    final metadata = await delegate.metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: ConfigProfileService.defaultClaudeMetadata,
      directories: [workingDirectory, ...additionalDirectories],
    );
    await delegate.fs.atomicWrite(
      metadataPath,
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
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
      scope.teamId,
      scope.sessionId,
      'claude',
    );
    final rosterDir = delegate.pathContext.join(
      claudeDir,
      'teams',
      ClaudeTeamRosterService.safeClaudePathSegment(scope.cliTeamName),
    );
    final rosterPath = delegate.pathContext.join(rosterDir, 'config.json');

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

  Future<void> _writeMemberProfiles({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required Map<String, Object?>? providerSettings,
    required Map<String, Map<String, Object?>> providerSettingsByMember,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    String? idleUrl,
  }) async {
    final uniqueMembers = <String, TeamMemberConfig>{};
    for (final member in members.where((member) => member.isValid)) {
      uniqueMembers[member.id] = member;
    }
    final selected = launchedMember;
    if (selected != null && selected.isValid) {
      uniqueMembers[selected.id] = selected;
    }

    for (final member in uniqueMembers.values) {
      await _writeMemberProfile(
        delegate: delegate,
        scope: scope,
        member: member,
        providerSettings:
            providerSettingsByMember[member.id] ?? providerSettings,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
        mixed: mixed,
        idleUrl: idleUrl,
      );
    }
  }

  Future<void> _writeMemberProfile({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamMemberConfig member,
    required Map<String, Object?>? providerSettings,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    String? idleUrl,
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.teamId,
      scope.sessionId,
      'claude',
    );
    final isLead = TeamMemberNaming.isTeamLead(member);
    await MemberRoleProvision.syncRolePromptFile(
      fs: delegate.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
      mixed: mixed,
    );
    final file = delegate.sessionClaudeMemberSettingsFile(
      scope.teamId,
      scope.sessionId,
      member,
    );
    var settings = _memberSettings(providerSettings, member);
    settings = MemberRoleProvision.applyTeamSessionPolicy(settings);
    if (mixed && idleUrl != null && idleUrl.isNotEmpty) {
      settings = mergeStopIdleHook(settings, member.id, idleUrl);
    }
    settings = await delegate.maybeApplyTeamLeadHooks(
      settings,
      member,
      memberToolDir,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
    );
    await delegate.writeSettingsFile(file, settings, memberToolDir: memberToolDir);
  }

  Future<Map<String, Map<String, Object?>>> _loadMemberProviderSettings({
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
      }
    }
    return settingsByMember;
  }

  static Map<String, Object?> _teamSettings(
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
  }) {
    final settings = <String, Object?>{
      if (providerSettings != null) ...providerSettings,
    };
    final env = <String, Object?>{};
    final existingEnv = settings['env'];
    if (existingEnv is Map) {
      for (final entry in existingEnv.entries) {
        final key = entry.key;
        if (key is String) {
          env[key] = entry.value;
        }
      }
    }
    env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1';
    env['CLAUDE_CODE_NO_FLICKER'] = '1';
    env.putIfAbsent('CCGUI_CLI_LOGIN_AUTHORIZED', () => '1');
    env.putIfAbsent('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', () => '1');
    settings['env'] = env;
    settings['effortLevel'] = effortLevel;
    settings['skipDangerousModePermissionPrompt'] = true;
    settings['teammateMode'] = teammateMode;
    return settings;
  }

  static Map<String, Object?> _memberSettings(
    Map<String, Object?>? providerSettings,
    TeamMemberConfig member,
  ) {
    final settings = _teamSettings(
      providerSettings,
      effortLevel: 'xhigh',
      teammateMode: 'in-process',
    );
    final model = member.model.trim();
    if (model.isNotEmpty) {
      final env = Map<String, Object?>.from(settings['env'] as Map);
      env['ANTHROPIC_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = model;
      settings['env'] = env;
    }
    return settings;
  }
}

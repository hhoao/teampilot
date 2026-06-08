import 'dart:convert';

import '../../../../models/claude_credential_link_result.dart';
import '../../../../models/project_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/team_member_naming.dart';
import '../../../provider/claude/claude_effort_capability.dart';
import '../../../provider/claude/claude_official_provider.dart';
import '../capabilities/cli_effort_capability.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../provider/claude/claude_provider_credentials_service.dart';
import '../../../provider/claude/claude_provider_settings_resolver.dart';
import '../../../session/member_role_provision.dart';
import '../../../team/claude_team_roster_service.dart';
import '../capabilities/config_profile_capability.dart';
import 'bus_idle_stop_hook.dart';

class ClaudeLaunchExtras {
  const ClaudeLaunchExtras({
    this.settings,
    this.providerId,
    this.settingsByMember = const {},
  });

  final Map<String, Object?>? settings;
  final String? providerId;
  final Map<String, Map<String, Object?>> settingsByMember;
}

final class ClaudeConfigProfileCapability implements ConfigProfileCapability {
  const ClaudeConfigProfileCapability();

  static const toolId = 'claude';
  static const metadataFileName = '.claude.json';
  static const settingsFileEnvKey = 'TEAMPILOT_CLAUDE_SETTINGS_FILE';

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
    'projectOnboardingSeenCount': 1,
    'hasClaudeMdExternalIncludesApproved': true,
    'hasClaudeMdExternalIncludesWarningShown': true,
    'allowedTools': <Object?>[],
    'mcpServers': <String, Object?>{},
  };

  static String sessionMetadataFile(
    ConfigProfileDelegate delegate,
    String teamId,
    String sessionId,
  ) =>
      delegate.pathContext.join(
        delegate.sessionToolDir(teamId, sessionId, toolId),
        metadataFileName,
      );

  static String sessionMemberSettingsFile(
    ConfigProfileDelegate delegate,
    String teamId,
    String sessionId,
    TeamMemberConfig member,
  ) =>
      delegate.pathContext.join(
        delegate.sessionToolDir(teamId, sessionId, toolId),
        'settings',
        '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
      );

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
    final standalone = ctx.standaloneScope;
    final profile = ctx.profile;
    if (standalone != null && profile != null) {
      await _ensureSessionDefaultsAt(
        ctx.paths,
        standaloneSessionToolDir(ctx.paths, standalone, toolId),
      );
      return;
    }
    await _ensureSessionDefaults(ctx.paths, ctx.teamId, ctx.sessionId);
  }

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final standalone = ctx.standaloneScope;
    final profile = ctx.profile;
    if (standalone != null && profile != null) {
      return _contributeStandaloneLaunch(ctx, standalone, profile);
    }

    final delegate = ctx.paths;
    final scope = ctx.scope;
    final workingDirectory = ctx.workingDirectory ?? '';
    final team = ctx.team;
    final warnings = <String>[];
    final mixed = team?.teamMode == TeamMode.mixed;

    ClaudeLaunchExtras? claude;
    if (team != null) {
      final resolver = ClaudeProviderSettingsResolver(
        basePath: delegate.basePath,
        repository: AppProviderRepository(
          basePath: delegate.basePath,
          fs: delegate.fs,
        ),
      );
      claude = await resolveLaunchExtras(
        team: team,
        member: ctx.member,
        resolver: resolver,
      );
    }

    await _writeMetadata(
      delegate,
      scope,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    final effortLevel = _resolveClaudeEffort(
      team: team,
      member: ctx.member,
      model: ctx.member?.model ?? '',
    );
    await _writeSettings(
      delegate,
      scope,
      claude?.settings,
      effortLevel: effortLevel,
      teammateMode: team?.claudeTeammateMode ?? 'in-process',
      mixed: mixed,
    );
    if (!mixed) {
      await _writeRoster(
        delegate: delegate,
        scope: scope,
        members: ctx.members,
        workingDirectory: workingDirectory,
        description: team?.description ?? '',
        leadSessionId: ctx.leadSessionId,
        teammateMode: team?.claudeTeammateMode ?? 'in-process',
      );
    }
    await _writeMemberProfiles(
      delegate: delegate,
      scope: scope,
      team: team,
      members: ctx.members,
      launchedMember: ctx.member,
      providerSettings: claude?.settings,
      providerSettingsByMember: claude?.settingsByMember ?? const {},
      forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
      mixed: mixed,
      idleUrl: ctx.busIdleUrl,
    );

    final providerId = claude?.providerId?.trim() ?? '';
    if (providerId.isNotEmpty &&
        claude?.settings != null &&
        isOfficialClaudeSettings(claude!.settings!)) {
      final sessionClaudeDir = delegate.sessionToolDir(
        scope.teamId,
        scope.sessionId,
        toolId,
      );
      final credentials = ClaudeProviderCredentialsService(
        fs: delegate.fs,
        basePath: delegate.basePath,
      );
      final link = await credentials.ensureLinked(
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
        toolId,
      ),
      if (member != null && member.isValid)
        settingsFileEnvKey: sessionMemberSettingsFile(
          delegate,
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
        tool: toolId,
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
    await _ensureSessionDefaultsAt(
      delegate,
      delegate.sessionToolDir(teamId, sessionId, toolId),
    );
  }

  Future<void> _ensureSessionDefaultsAt(
    ConfigProfileDelegate delegate,
    String memberToolDir,
  ) async {
    final file = delegate.pathContext.join(memberToolDir, metadataFileName);
    final existing = await delegate.readMetadataFile(file, defaultMetadata);
    await delegate.writeJsonIfChanged(file, {
      ...defaultMetadata,
      ...existing,
    });
  }

  Future<ConfigProfileLaunchContribution> _contributeStandaloneLaunch(
    ConfigProfileLaunchContext ctx,
    StandaloneLaunchProfileScope standalone,
    ProjectProfile profile,
  ) async {
    final delegate = ctx.paths;
    final member = standaloneMemberFromProfile(profile);
    final memberToolDir = standaloneSessionToolDir(delegate, standalone, toolId);
    final scope = launchScopeForStandalone(standalone);
    final workingDirectory = ctx.workingDirectory ?? '';
    final warnings = <String>[];

    final resolver = ClaudeProviderSettingsResolver(
      basePath: delegate.basePath,
      repository: AppProviderRepository(
        basePath: delegate.basePath,
        fs: delegate.fs,
      ),
    );
    final providerId = standaloneProviderId(profile);
    final settings = await resolver.resolve(
      providerId.isNotEmpty ? providerId : null,
    );
    final resolvedProviderId = providerId.isNotEmpty
        ? providerId
        : (settings != null
              ? (await _resolveSoleClaudeProviderId(delegate))
              : null);

    await _writeMetadataAt(
      delegate,
      memberToolDir,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    final effortLevel = _resolveClaudeEffort(
      team: null,
      member: member,
      model: member.model.isNotEmpty ? member.model : profile.agent.model,
      profileEffort: profile.agent.effort.isNotEmpty
          ? profile.agent.effort
          : profile.effortsByTool[toolId],
    );
    await _writeSettingsAt(
      delegate,
      memberToolDir,
      scope,
      settings,
      effortLevel: effortLevel,
      standalone: true,
    );
    await _writeStandaloneMemberProfile(
      delegate: delegate,
      memberToolDir: memberToolDir,
      scope: scope,
      member: member,
      providerSettings: settings,
      team: null,
      effortLevel: effortLevel,
    );

    final trimmedProviderId = resolvedProviderId?.trim() ?? '';
    if (trimmedProviderId.isNotEmpty &&
        settings != null &&
        isOfficialClaudeSettings(settings)) {
      final credentials = ClaudeProviderCredentialsService(
        fs: delegate.fs,
        basePath: delegate.basePath,
      );
      final link = await credentials.ensureLinked(
        memberToolDir,
        trimmedProviderId,
      );
      if (link == CredentialLinkResult.missing) {
        warnings.add('claude_credentials_missing');
      }
    }

    final environment = <String, String>{
      'CLAUDE_CONFIG_DIR': memberToolDir,
      if (member.isValid)
        settingsFileEnvKey: delegate.pathContext.join(
          memberToolDir,
          'settings',
          '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
        ),
      'CLAUDE_CODE_NO_FLICKER': '1',
    };

    if (member.isValid) {
      final appendPath = await delegate.resolveAppendSystemPromptPath(
        scope: scope,
        tool: toolId,
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

  Future<String?> _resolveSoleClaudeProviderId(
    ConfigProfileDelegate delegate,
  ) async {
    final providers = await AppProviderRepository(
      basePath: delegate.basePath,
      fs: delegate.fs,
    ).loadProviders(CliTool.claude);
    if (providers.length == 1) return providers.first.id;
    return null;
  }

  Future<void> _writeMetadataAt(
    ConfigProfileDelegate delegate,
    String memberToolDir,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = delegate.pathContext.join(
      memberToolDir,
      metadataFileName,
    );
    final metadata = await delegate.metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: defaultMetadata,
      defaultProjectConfig: defaultProjectConfig,
      directories: [workingDirectory, ...additionalDirectories],
    );
    await delegate.fs.atomicWrite(
      metadataPath,
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  Future<void> _writeSettingsAt(
    ConfigProfileDelegate delegate,
    String memberToolDir,
    LaunchProfileScope scope,
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    String teammateMode = 'in-process',
    bool mixed = false,
    bool standalone = false,
  }) async {
    final file = delegate.pathContext.join(memberToolDir, 'settings.json');
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
      mixed: mixed,
      standalone: standalone,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      teamId: standalone ? null : scope.teamId,
      projectId: standalone ? scope.teamId : null,
    );
  }

  Future<void> _writeStandaloneMemberProfile({
    required ConfigProfileDelegate delegate,
    required String memberToolDir,
    required LaunchProfileScope scope,
    required TeamMemberConfig member,
    required Map<String, Object?>? providerSettings,
    required TeamConfig? team,
    required String effortLevel,
  }) async {
    await MemberRoleProvision.syncRolePromptFile(
      fs: delegate.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: false,
      mixed: false,
    );
    final file = delegate.pathContext.join(
      memberToolDir,
      'settings',
      '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
    );
    final settings = _memberSettings(
      providerSettings,
      member,
      effortLevel: effortLevel,
      mixed: false,
      standalone: true,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      projectId: scope.teamId,
    );
  }

  Future<void> _writeSettings(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
    required bool mixed,
  }) async {
    final file = delegate.pathContext.join(
      delegate.sessionToolDir(scope.teamId, scope.sessionId, toolId),
      'settings.json',
    );
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
      mixed: mixed,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: delegate.sessionToolDir(
        scope.teamId,
        scope.sessionId,
        toolId,
      ),
      tool: toolId,
      teamId: scope.teamId,
    );
  }

  Future<void> _writeMetadata(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = sessionMetadataFile(
      delegate,
      scope.teamId,
      scope.sessionId,
    );
    final metadata = await delegate.metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: defaultMetadata,
      defaultProjectConfig: defaultProjectConfig,
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
      toolId,
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
    required TeamConfig? team,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required Map<String, Object?>? providerSettings,
    required Map<String, Map<String, Object?>> providerSettingsByMember,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    String? idleUrl,
  }) async {
    final selected = launchedMember;
    final uniqueMembers = <String, TeamMemberConfig>{};
    if (!mixed) {
      for (final member in members.where((member) => member.isValid)) {
        uniqueMembers[member.id] = member;
      }
    }
    if (selected != null && selected.isValid) {
      uniqueMembers[selected.id] = selected;
    }

    for (final member in uniqueMembers.values) {
      await _writeMemberProfile(
        delegate: delegate,
        scope: scope,
        team: team,
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
    required TeamConfig? team,
    required TeamMemberConfig member,
    required Map<String, Object?>? providerSettings,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    String? idleUrl,
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.teamId,
      scope.sessionId,
      toolId,
    );
    final isLead = TeamMemberNaming.isTeamLead(member);
    await MemberRoleProvision.syncRolePromptFile(
      fs: delegate.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
      mixed: mixed,
    );
    final file = sessionMemberSettingsFile(
      delegate,
      scope.teamId,
      scope.sessionId,
      member,
    );
    final effortLevel = _resolveClaudeEffort(
      team: team,
      member: member,
      model: member.model,
    );
    var settings = _memberSettings(
      providerSettings,
      member,
      effortLevel: effortLevel,
      mixed: mixed,
    );
    settings = MemberRoleProvision.applyTeamSessionPolicy(settings, mixed: mixed);
    if (mixed && idleUrl != null && idleUrl.isNotEmpty) {
      settings = mergeStopIdleHook(settings, member.id, idleUrl);
    }
    settings = await delegate.maybeApplyTeamLeadHooks(
      settings,
      member,
      memberToolDir,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      teamId: scope.teamId,
    );
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
    required bool mixed,
    bool standalone = false,
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
    if (mixed || standalone) {
      env.remove('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS');
    } else {
      env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1';
    }
    env['CLAUDE_CODE_NO_FLICKER'] = '1';
    env.putIfAbsent('CCGUI_CLI_LOGIN_AUTHORIZED', () => '1');
    env.putIfAbsent('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', () => '1');
    settings['env'] = env;
    settings['effortLevel'] = effortLevel;
    settings['skipDangerousModePermissionPrompt'] = true;
    if (mixed || standalone) {
      settings.remove('teammateMode');
    } else {
      settings['teammateMode'] = teammateMode;
    }
    return settings;
  }

  static String _resolveClaudeEffort({
    required TeamConfig? team,
    required TeamMemberConfig? member,
    required String model,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = ClaudeEffortCapability();
    return resolveLaunchEffort(
      capability: capability,
      cli: CliTool.claude,
      context: EffortResolveContext(
        team: team,
        member: member,
        model: model,
      ),
    );
  }

  static Map<String, Object?> _memberSettings(
    Map<String, Object?>? providerSettings,
    TeamMemberConfig member, {
    required String effortLevel,
    required bool mixed,
    bool standalone = false,
  }) {
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: 'in-process',
      mixed: mixed,
      standalone: standalone,
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

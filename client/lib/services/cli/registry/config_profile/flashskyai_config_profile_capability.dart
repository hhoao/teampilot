import '../../../../models/personal_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/team_member_naming.dart';
import '../../../provider/flashskyai/flashskyai_effort_capability.dart';
import '../../../session/member_role_provision.dart';
import '../capabilities/cli_effort_capability.dart';
import '../capabilities/config_profile_capability.dart';
import 'bus_idle_stop_hook.dart';

final class FlashskyaiConfigProfileCapability
    implements ConfigProfileCapability {
  const FlashskyaiConfigProfileCapability();

  static const toolId = 'flashskyai';
  static const metadataFileName = '.flashskyai.json';
  static const settingsFileName = 'settings.json';
  static const configDirEnvKey = 'FLASHSKYAI_CONFIG_DIR';
  static const sessionHomeDirEnvKey = 'FLASHSKYAI_SESSION_HOME_DIR';

  static const defaultMetadata = <String, Object?>{
    'hasCompletedOnboarding': true,
    // Follow the embedded terminal's light/dark out of the box (no `/theme`),
    // resolved from the COLORFGBG we inject at launch. Seed-only: a later user
    // `/theme` choice is persisted and wins via `{...defaults, ...existing}`.
    // See ClaudeConfigProfileCapability.defaultMetadata for the rationale.
    'theme': 'auto',
  };

  static const defaultWorkspaceConfig = <String, Object?>{
    'hasTrustDialogAccepted': true,
    'workspaceOnboardingSeenCount': 1,
    'allowedTools': <Object?>[],
    'mcpServers': <String, Object?>{},
  };

  static String sessionMetadataFile(
    ConfigProfileDelegate delegate,
    String workspaceId,
    String sessionId, {
    String? memberId,
  }) =>
      delegate.pathContext.join(
        delegate.sessionToolDir(
          workspaceId,
          sessionId,
          toolId,
          memberId: memberId,
        ),
        metadataFileName,
      );

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {
    final delegate = ctx.paths;
    await delegate.layout.ensureAppToolLayout(toolId);
    final standalone = ctx.standaloneScope;
    final personal = ctx.personal;
    if (standalone != null && personal != null) {
      await _ensureSessionDefaultsAt(
        delegate,
        standaloneSessionToolDir(delegate, standalone, toolId),
      );
      return;
    }
    await _ensureSessionDefaults(
      delegate,
      ctx.workspaceId,
      ctx.sessionId,
      memberId: ctx.memberId,
    );
  }

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final standalone = ctx.standaloneScope;
    final personal = ctx.personal;
    if (standalone != null && personal != null) {
      return _contributeStandaloneLaunch(ctx, standalone, personal);
    }

    final delegate = ctx.paths;
    final scope = ctx.scope;
    final workingDirectory = ctx.workingDirectory ?? '';
    await _writeMetadata(
      delegate,
      scope,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    await _writeMemberProfiles(
      delegate: delegate,
      scope: scope,
      team: ctx.team,
      members: ctx.members,
      launchedMember: ctx.member,
      forceTeamLeadDelegateMode: ctx.team?.forceTeamLeadDelegateMode ?? false,
      mixed: ctx.team?.teamMode == TeamMode.mixed,
      idleUrl: ctx.busIdleUrl,
      effortLevel: _resolveFlashskyaiEffort(
        team: ctx.team,
        member: ctx.member,
        model: ctx.member?.model ?? '',
      ),
    );

    final environment = _teamLaunchEnvironment(delegate, scope);
    final member = ctx.member;
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

    return ConfigProfileLaunchContribution(environment: environment);
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
    PersonalProfile personal,
  ) async {
    final delegate = ctx.paths;
    final member = standaloneMemberFromPersonal(personal, preset: ctx.preset);
    final memberToolDir = standaloneSessionToolDir(delegate, standalone, toolId);
    final scope = launchScopeForStandalone(standalone);
    final workingDirectory = ctx.workingDirectory ?? '';

    await _writeMetadataAt(
      delegate,
      memberToolDir,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    await _writeStandaloneMemberProfile(
      delegate: delegate,
      memberToolDir: memberToolDir,
      scope: scope,
      member: member,
      effortLevel: _resolveFlashskyaiEffort(
        team: null,
        member: member,
        model: member.model,
        profileEffort: ctx.preset?.effort ?? '',
      ),
    );

    final environment = _standaloneLaunchEnvironment(delegate, memberToolDir);
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

    return ConfigProfileLaunchContribution(environment: environment);
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
    final directories = [workingDirectory, ...additionalDirectories];
    if (await delegate.trustedProjectsAlreadyCurrent(
      metadataPath,
      directories,
      defaultMetadata: defaultMetadata,
    )) {
      return;
    }
    final metadata = await delegate.metadataWithTrustedWorkspaces(
      metadataPath: metadataPath,
      defaultMetadata: defaultMetadata,
      defaultWorkspaceConfig: defaultWorkspaceConfig,
      directories: directories,
    );
    await delegate.writeJsonIfChanged(metadataPath, metadata);
  }

  Future<void> _writeStandaloneMemberProfile({
    required ConfigProfileDelegate delegate,
    required String memberToolDir,
    required LaunchProfileScope scope,
    required TeamMemberConfig member,
    required String effortLevel,
  }) async {
    await MemberRoleProvision.syncRolePromptFile(
      fs: delegate.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: false,
      mixed: false,
    );
    final settingsFile = delegate.pathContext.join(
      memberToolDir,
      settingsFileName,
    );
    final settings = _memberSettings(member, effortLevel: effortLevel);
    await delegate.writeSettingsFile(
      settingsFile,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      workspaceId: scope.teamId,
    );
  }

  Map<String, String> _standaloneLaunchEnvironment(
    ConfigProfileDelegate delegate,
    String memberToolDir,
  ) {
    return {
      configDirEnvKey: memberToolDir,
      sessionHomeDirEnvKey: memberToolDir,
      'LLM_CONFIG_PATH': delegate.layout.appFlashskyaiLlmConfigFile,
      'FLASHSKYAI_CODE_NO_FLICKER': '1',
    };
  }

  Future<void> _writeMetadata(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = sessionMetadataFile(
      delegate,
      scope.workspaceId,
      scope.sessionId,
      memberId: scope.memberId,
    );
    final directories = [workingDirectory, ...additionalDirectories];
    if (await delegate.trustedProjectsAlreadyCurrent(
      metadataPath,
      directories,
      defaultMetadata: defaultMetadata,
    )) {
      return;
    }
    final metadata = await delegate.metadataWithTrustedWorkspaces(
      metadataPath: metadataPath,
      defaultMetadata: defaultMetadata,
      defaultWorkspaceConfig: defaultWorkspaceConfig,
      directories: directories,
    );
    await delegate.writeJsonIfChanged(metadataPath, metadata);
  }

  Future<void> _writeMemberProfiles({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamProfile? team,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    String? idleUrl,
    required String effortLevel,
  }) async {
    final selected = launchedMember;
    if (selected == null || !selected.isValid) {
      await _writeTeamSettings(delegate, scope, effortLevel: effortLevel);
      return;
    }
    await _writeMemberProfile(
      delegate: delegate,
      scope: scope,
      member: selected,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: mixed,
      idleUrl: idleUrl,
      effortLevel: effortLevel,
    );
  }

  Future<void> _writeTeamSettings(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope, {
    required String effortLevel,
  }) async {
    final file = delegate.pathContext.join(
      delegate.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        toolId,
        memberId: scope.memberId,
      ),
      settingsFileName,
    );
    final memberToolDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final teamDefaults = _teamSettings(effortLevel: effortLevel);
    if (await _settingsAlreadyCurrent(delegate, file, teamDefaults) &&
        !await delegate.hasEnabledExtensionSettingsHooks(
          toolId,
          teamId: scope.teamId,
        )) {
      return;
    }
    var merged = await _teamSettingsMerged(delegate, file, effortLevel: effortLevel);
    merged = await delegate.applyExtensionSettings(
      merged,
      memberToolDir,
      tool: toolId,
      teamId: scope.teamId,
    );
    await delegate.writeJsonIfChanged(file, merged);
  }

  Future<void> _writeMemberProfile({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamMemberConfig member,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    String? idleUrl,
    required String effortLevel,
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final isLead = TeamMemberNaming.isTeamLead(member);
    await MemberRoleProvision.syncRolePromptFile(
      fs: delegate.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
      mixed: mixed,
    );
    final settingsFile = delegate.pathContext.join(
      memberToolDir,
      settingsFileName,
    );
    var settings = _memberSettings(member, effortLevel: effortLevel);
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
      settingsFile,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      teamId: scope.teamId,
    );
  }

  Map<String, String> _teamLaunchEnvironment(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
  ) {
    final memberDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    return {
      configDirEnvKey: memberDir,
      sessionHomeDirEnvKey: memberDir,
      'LLM_CONFIG_PATH': delegate.layout.appFlashskyaiLlmConfigFile,
      'FLASHSKYAI_CODE_NO_FLICKER': '1',
    };
  }

  Future<bool> _settingsAlreadyCurrent(
    ConfigProfileDelegate delegate,
    String path,
    Map<String, Object?> teamDefaults,
  ) async {
    if (!(await delegate.fs.stat(path)).isFile) return false;
    final existing = await delegate.readSettingsFile(path);
    for (final entry in teamDefaults.entries) {
      if (entry.key == 'enabledPlugins') continue;
      if (existing[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<Map<String, Object?>> _teamSettingsMerged(
    ConfigProfileDelegate delegate,
    String path, {
    required String effortLevel,
  }) async {
    final existing = await delegate.readSettingsFile(path);
    final merged = Map<String, Object?>.from(_teamSettings(effortLevel: effortLevel));
    final enabledPlugins = existing['enabledPlugins'];
    if (enabledPlugins is Map && enabledPlugins.isNotEmpty) {
      merged['enabledPlugins'] = enabledPlugins;
    }
    return merged;
  }

  static Map<String, Object?> _teamSettings({required String effortLevel}) {
    return <String, Object?>{
      'skipDangerousModePermissionPrompt': true,
      if (effortLevel.isNotEmpty) 'effortLevel': effortLevel,
    };
  }

  static Map<String, Object?> _memberSettings(
    TeamMemberConfig member, {
    required String effortLevel,
  }) {
    return Map<String, Object?>.from(_teamSettings(effortLevel: effortLevel));
  }

  static String _resolveFlashskyaiEffort({
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required String model,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = FlashskyaiEffortCapability();
    return resolveLaunchEffort(
      capability: capability,
      cli: CliTool.flashskyai,
      context: EffortResolveContext(
        team: team,
        member: member,
        model: model,
      ),
    );
  }
}

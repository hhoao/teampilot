import '../../../../models/team_config.dart';
import '../../../../utils/team_member_naming.dart';
import '../../../provider/config_profile_service.dart';
import '../../../session/member_role_provision.dart';
import '../capabilities/config_profile_capability.dart';
import '../config_profile/config_profile_context.dart';

final class FlashskyaiConfigProfileCapability
    implements ConfigProfileCapability {
  const FlashskyaiConfigProfileCapability();

  static const metadataFileName = '.flashskyai.json';
  static const settingsFileName = 'settings.json';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {
    final delegate = ctx.paths;
    await delegate.layout.ensureAppToolLayout('flashskyai');
    await _ensureSessionDefaults(delegate, ctx.teamId, ctx.sessionId);
  }

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
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
      members: ctx.members,
      launchedMember: ctx.member,
      forceTeamLeadDelegateMode: ctx.team?.forceTeamLeadDelegateMode ?? false,
      mixed: ctx.team?.teamMode == TeamMode.mixed,
    );

    final environment = _teamLaunchEnvironment(delegate, scope);
    final member = ctx.member;
    if (member != null && member.isValid) {
      final appendPath = await delegate.resolveAppendSystemPromptPath(
        scope: scope,
        tool: 'flashskyai',
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
    String teamId,
    String sessionId,
  ) async {
    final file = delegate.sessionFlashskyaiMetadataFile(teamId, sessionId);
    final existing = await delegate.readMetadataFile(
      file,
      ConfigProfileService.defaultFlashskyaiMetadata,
    );
    await delegate.writeJsonIfChanged(file, {
      ...ConfigProfileService.defaultFlashskyaiMetadata,
      ...existing,
    });
  }

  Future<void> _writeMetadata(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = delegate.sessionFlashskyaiMetadataFile(
      scope.teamId,
      scope.sessionId,
    );
    final directories = [workingDirectory, ...additionalDirectories];
    if (await delegate.trustedProjectsAlreadyCurrent(
      metadataPath,
      directories,
    )) {
      return;
    }
    final metadata = await delegate.metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: ConfigProfileService.defaultFlashskyaiMetadata,
      directories: directories,
    );
    await delegate.writeJsonIfChanged(metadataPath, metadata);
  }

  Future<void> _writeMemberProfiles({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
  }) async {
    final selected = launchedMember;
    if (selected == null || !selected.isValid) {
      await _writeTeamSettings(delegate, scope);
      return;
    }
    await _writeMemberProfile(
      delegate: delegate,
      scope: scope,
      member: selected,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: mixed,
    );
  }

  Future<void> _writeTeamSettings(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
  ) async {
    final file = delegate.pathContext.join(
      delegate.sessionToolDir(scope.teamId, scope.sessionId, 'flashskyai'),
      settingsFileName,
    );
    final memberToolDir = delegate.sessionToolDir(
      scope.teamId,
      scope.sessionId,
      'flashskyai',
    );
    final teamDefaults = _teamSettings();
    if (await _settingsAlreadyCurrent(delegate, file, teamDefaults) &&
        !await delegate.isRtkEnabled()) {
      return;
    }
    var merged = await _teamSettingsMerged(delegate, file);
    merged = await delegate.maybeApplyRtk(merged, memberToolDir);
    await delegate.writeJsonIfChanged(file, merged);
  }

  Future<void> _writeMemberProfile({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamMemberConfig member,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.teamId,
      scope.sessionId,
      'flashskyai',
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
    var settings = _memberSettings(member);
    settings = MemberRoleProvision.applyTeamSessionPolicy(settings);
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
    );
  }

  Map<String, String> _teamLaunchEnvironment(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
  ) {
    final memberDir = delegate.sessionToolDir(
      scope.teamId,
      scope.sessionId,
      'flashskyai',
    );
    return {
      ConfigProfileService.flashskyaiConfigDirEnvKey: memberDir,
      ConfigProfileService.flashskyaiSessionHomeDirEnvKey: memberDir,
      'LLM_CONFIG_PATH': delegate.appFlashskyaiLlmConfigFile,
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
    String path,
  ) async {
    final existing = await delegate.readSettingsFile(path);
    final merged = Map<String, Object?>.from(_teamSettings());
    final enabledPlugins = existing['enabledPlugins'];
    if (enabledPlugins is Map && enabledPlugins.isNotEmpty) {
      merged['enabledPlugins'] = enabledPlugins;
    }
    return merged;
  }

  static Map<String, Object?> _teamSettings() {
    return <String, Object?>{'skipDangerousModePermissionPrompt': true};
  }

  static Map<String, Object?> _memberSettings(TeamMemberConfig member) {
    return Map<String, Object?>.from(_teamSettings());
  }
}

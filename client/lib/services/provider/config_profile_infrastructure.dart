import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/extension_manifest.dart';
import '../../models/team_config.dart';
import '../../utils/workspace_path_utils.dart';
import '../../utils/team_member_naming.dart';
import '../storage/runtime_layout.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../extension/builtin_manifests.dart';
import '../extension/extension_detector.dart';
import '../extension/extension_provisioner.dart';
import '../host/bundled_asset_loader.dart';
import '../host/host_execution_environment.dart';
import '../host/host_script_dialect.dart';
import '../host/script_file_hook_provisioner.dart';
import '../host/team_pilot_hook_scripts.dart';
import '../io/filesystem.dart';
import '../session/member_role_provision.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_storage_context.dart';
import '../team/team_lead_delegate_settings_merge.dart';
import '../team/team_lead_settings_merge.dart';

/// Cross-CLI config profile file I/O, trusted-workspace metadata, extensions, hooks.
final class ConfigProfileInfrastructure implements ConfigProfileDelegate {
  ConfigProfileInfrastructure({
    required this.basePath,
    required this.layout,
    String? home,
    Filesystem? fs,
    Future<Set<String>> Function({String? teamId, String? workspaceId})?
    loadEnabledExtensionIds,
    ExtensionDetector? extensionDetector,
    List<ExtensionManifest>? extensionManifests,
    Map<String, ScriptFileHookProvisioner>? extensionHookProvisioners,
    ScriptFileHookProvisioner? teamLeadHookProvisioner,
    Future<String> Function(HostScriptDialect dialect)? loadTeamLeadHookScript,
    ScriptFileHookProvisioner? teamLeadDelegateHookProvisioner,
    Future<String> Function(HostScriptDialect dialect)?
    loadTeamLeadDelegateHookScript,
    HostExecutionEnvironment? hostEnvironment,
  }) : _fs = fs ?? AppStorage.fs,
       _loadEnabledExtensionIds = loadEnabledExtensionIds,
       _extensionDetector = extensionDetector,
       _extensionManifests = extensionManifests,
       _extensionHookProvisioners = extensionHookProvisioners,
       _teamLeadHookProvisioner = teamLeadHookProvisioner,
       _loadTeamLeadHookScript = loadTeamLeadHookScript,
       _teamLeadDelegateHookProvisioner = teamLeadDelegateHookProvisioner,
       _loadTeamLeadDelegateHookScript = loadTeamLeadDelegateHookScript,
       _hostEnvironment = hostEnvironment,
       _homeOverride = home?.trim();

  @override
  final String basePath;
  final String? _homeOverride;
  @override
  final RuntimeLayout layout;
  final Filesystem _fs;
  final Future<Set<String>> Function({String? teamId, String? workspaceId})?
  _loadEnabledExtensionIds;
  final ExtensionDetector? _extensionDetector;
  final List<ExtensionManifest>? _extensionManifests;
  final Map<String, ScriptFileHookProvisioner>? _extensionHookProvisioners;
  final ScriptFileHookProvisioner? _teamLeadHookProvisioner;
  final Future<String> Function(HostScriptDialect dialect)? _loadTeamLeadHookScript;
  final ScriptFileHookProvisioner? _teamLeadDelegateHookProvisioner;
  final Future<String> Function(HostScriptDialect dialect)?
  _loadTeamLeadDelegateHookScript;
  final HostExecutionEnvironment? _hostEnvironment;

  @override
  Filesystem get fs => _fs;

  @override
  @override
  String get home {
    final override = _homeOverride;
    if (override != null && override.isNotEmpty) return override;
    if (RuntimeStorageContext.isInstalled) {
      return RuntimeStorageContext.current.home;
    }
    return '';
  }

  @override
  p.Context get pathContext => _fs.pathContext;

  @override
  String sessionToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) =>
      layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        tool,
        memberId: memberId,
      );

  @override
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) =>
      _readMetadataFile(path, defaults);

  @override
  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value) =>
      _writeJsonIfChanged(path, value);

  @override
  Future<Map<String, Object?>> metadataWithTrustedWorkspaces({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultWorkspaceConfig,
    required Iterable<String> directories,
  }) async {
    final metadata = await _readMetadataFile(metadataPath, defaultMetadata);
    final trustedKeys = <String>{
      for (final dir in directories) ...workspaceMetadataKeys(dir),
    };
    if (trustedKeys.isEmpty) {
      return metadata;
    }

    final existingWorkspaces = metadata['workspaces'];
    final workspaces = existingWorkspaces is Map
        ? Map<String, Object?>.from(
            existingWorkspaces.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : <String, Object?>{};

    for (final key in trustedKeys) {
      final existing = workspaces[key];
      final workspaceConfig = existing is Map
          ? Map<String, Object?>.from(
              existing.map(
                (entryKey, value) => MapEntry(entryKey.toString(), value),
              ),
            )
          : <String, Object?>{...defaultWorkspaceConfig};
      for (final entry in defaultWorkspaceConfig.entries) {
        workspaceConfig.putIfAbsent(entry.key, () => entry.value);
      }
      for (final entry in defaultWorkspaceConfig.entries) {
        if (entry.value == true) {
          workspaceConfig[entry.key] = true;
        }
      }
      workspaces[key] = workspaceConfig;
    }
    metadata['workspaces'] = workspaces;
    return metadata;
  }

  @override
  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  }) async {
    final trustedKeys = {
      for (final dir in directories) ...workspaceMetadataKeys(dir),
    };
    if (trustedKeys.isEmpty) return false;

    final metadata = await _readMetadataFile(metadataPath, defaultMetadata);
    final workspaces = metadata['workspaces'];
    if (workspaces is! Map) return false;

    for (final key in trustedKeys) {
      final workspace = workspaces[key];
      if (workspace is! Map) return false;
      if (workspace['hasTrustDialogAccepted'] != true) return false;
    }
    return true;
  }

  @override
  Future<Map<String, Object?>> readSettingsFile(String path) =>
      _readSettingsFile(path);

  @override
  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
    String? workspaceId,
  }) =>
      _writeSettingsFile(
        path,
        settings,
        memberToolDir: memberToolDir,
        tool: tool,
        teamId: teamId,
        workspaceId: workspaceId,
      );

  @override
  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
    String? workspaceId,
  }) =>
      _extensionProvisioner(teamId: teamId, workspaceId: workspaceId)
          .hasEnabledSettingsHooksForTool(tool);

  @override
  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  }) =>
      _extensionProvisioner(teamId: teamId, workspaceId: workspaceId).applySettings(
        settings,
        memberToolDir?.trim() ?? '',
        tool: tool,
      );

  @override
  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) async {
    if (!TeamMemberNaming.isTeamLead(member)) {
      return settings;
    }
    final host = hostEnvironmentForProvision();
    final selfTargetProvisioner = _resolveTeamLeadHookProvisioner(host);
    final selfScriptPath = await selfTargetProvisioner.provision(memberToolDir);
    var merged = const TeamLeadSettingsMerge().mergeIntoSettings(
      base: settings,
      hookCommand: selfTargetProvisioner.commandForPath(selfScriptPath),
    );
    merged = const TeamLeadDelegateSettingsMerge().stripFromSettings(merged);
    if (forceTeamLeadDelegateMode) {
      final delegateProvisioner = _resolveTeamLeadDelegateHookProvisioner(host);
      final delegateScriptPath = await delegateProvisioner.provision(
        memberToolDir,
      );
      merged = const TeamLeadDelegateSettingsMerge().mergeIntoSettings(
        base: merged,
        hookCommand: delegateProvisioner.commandForPath(delegateScriptPath),
      );
    }
    return merged;
  }

  @override
  Future<String?> resolveAppendSystemPromptPath({
    required LaunchProfileScope scope,
    required String tool,
    required TeamMemberConfig member,
  }) async {
    final path = MemberRoleProvision.rolePromptPath(
      sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        tool,
        memberId: scope.memberId,
      ),
      member,
    );
    final stat = await _fs.stat(path);
    if (!stat.exists) return null;
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    return path;
  }

  @override
  HostExecutionEnvironment hostEnvironmentForProvision() {
    if (_hostEnvironment != null) return _hostEnvironment;
    if (RuntimeStorageContext.isInstalled) {
      return HostExecutionEnvironment.fromStorage(RuntimeStorageContext.current);
    }
    return HostExecutionEnvironment.resolve();
  }

  Future<void> collectExtensionWarnings(
    List<String> warnings, {
    String? teamId,
    String? workspaceId,
  }) async {
    warnings.addAll(
      await _extensionProvisioner(teamId: teamId, workspaceId: workspaceId)
          .collectWarnings(),
    );
  }

  Future<void> _writeJsonIfChanged(
    String path,
    Map<String, Object?> value,
  ) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    final existing = await _fs.readString(path);
    if (existing == encoded) {
      return;
    }
    await _fs.atomicWrite(path, encoded);
  }

  Future<void> _writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
    String? workspaceId,
  }) async {
    final existing = await _readSettingsFile(path);
    final enabledPlugins = existing['enabledPlugins'];
    var merged = Map<String, Object?>.from(settings);
    if (enabledPlugins is Map && enabledPlugins.isNotEmpty) {
      merged['enabledPlugins'] = enabledPlugins;
    }
    merged = await applyExtensionSettings(
      merged,
      memberToolDir,
      tool: tool,
      teamId: teamId,
      workspaceId: workspaceId,
    );
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(merged),
    );
  }

  ExtensionProvisioner _extensionProvisioner({
    String? teamId,
    String? workspaceId,
  }) {
    return ExtensionProvisioner(
      manifests: _extensionManifests ?? builtInExtensionManifests(),
      isEnabled: (id) async => (await _enabledExtensionIds(
        teamId: teamId,
        workspaceId: workspaceId,
      )).contains(id),
      detector: _extensionDetector,
      hookProvisionerFor: _hookProvisionerForAsset,
    );
  }

  Future<Set<String>> _enabledExtensionIds({
    String? teamId,
    String? workspaceId,
  }) async {
    final loader = _loadEnabledExtensionIds;
    if (loader == null) return {};
    return loader(teamId: teamId, workspaceId: workspaceId);
  }

  ScriptFileHookProvisioner _hookProvisionerForAsset(String scriptAsset) {
    final override = _extensionHookProvisioners?[scriptAsset];
    if (override != null) return override;

    final host = hostEnvironmentForProvision();
    switch (scriptAsset) {
      case TeamPilotHookScripts.rtkRewrite:
        return ScriptFileHookProvisioner(
          fs: _fs,
          runner: host.scriptRunner,
          baseFileName: TeamPilotHookScripts.rtkRewrite,
          loadScript: (dialect) => loadBundledAssetString(
            switch (dialect) {
              HostScriptDialect.bash => 'assets/rtk/rtk-rewrite.sh',
              HostScriptDialect.powershell => 'assets/rtk/rtk-rewrite.ps1',
            },
          ),
        );
      default:
        throw StateError(
          'No bundled hook provisioner for extension script asset "$scriptAsset"',
        );
    }
  }

  ScriptFileHookProvisioner _resolveTeamLeadHookProvisioner(
    HostExecutionEnvironment host,
  ) {
    return _teamLeadHookProvisioner ??
        ScriptFileHookProvisioner(
          fs: _fs,
          runner: host.scriptRunner,
          baseFileName: TeamPilotHookScripts.teamLeadSelf,
          loadScript:
              _loadTeamLeadHookScript ??
              (dialect) => loadBundledAssetString(
                switch (dialect) {
                  HostScriptDialect.bash =>
                    'assets/hooks/teampilot-deny-team-lead-self-message.sh',
                  HostScriptDialect.powershell =>
                    'assets/hooks/teampilot-deny-team-lead-self-message.ps1',
                },
              ),
        );
  }

  ScriptFileHookProvisioner _resolveTeamLeadDelegateHookProvisioner(
    HostExecutionEnvironment host,
  ) {
    return _teamLeadDelegateHookProvisioner ??
        ScriptFileHookProvisioner(
          fs: _fs,
          runner: host.scriptRunner,
          baseFileName: TeamPilotHookScripts.teamLeadDelegate,
          loadScript:
              _loadTeamLeadDelegateHookScript ??
              (dialect) => loadBundledAssetString(
                switch (dialect) {
                  HostScriptDialect.bash =>
                    'assets/hooks/teampilot-team-lead-delegate-only.sh',
                  HostScriptDialect.powershell =>
                    'assets/hooks/teampilot-team-lead-delegate-only.ps1',
                },
              ),
        );
  }

  Future<Map<String, Object?>> _readSettingsFile(String path) async {
    if (!(await _fs.stat(path)).exists) return {};
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on Object {
      return {};
    }
    return {};
  }

  Future<Map<String, Object?>> _readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) async {
    if (!(await _fs.stat(path)).exists) {
      return {...defaults};
    }
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      return {...defaults};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on Object {
      return {...defaults};
    }
    return {...defaults};
  }
}

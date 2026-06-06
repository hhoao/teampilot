import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/extension_manifest.dart';
import '../../models/team_config.dart';
import '../../utils/project_path_utils.dart';
import '../../utils/team_member_naming.dart';
import '../cli/cli_data_layout.dart';
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

/// Cross-CLI config profile file I/O, trusted-project metadata, extensions, hooks.
final class ConfigProfileInfrastructure implements ConfigProfileDelegate {
  ConfigProfileInfrastructure({
    required this.basePath,
    required this.layout,
    Filesystem? fs,
    Future<Set<String>> Function({String? teamId, String? projectId})?
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
       _hostEnvironment = hostEnvironment;

  @override
  final String basePath;
  @override
  final CliDataLayout layout;
  final Filesystem _fs;
  final Future<Set<String>> Function({String? teamId, String? projectId})?
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
  p.Context get pathContext => _fs.pathContext;

  @override
  String sessionToolDir(String teamId, String sessionId, String tool) =>
      layout.memberToolDir(teamId, sessionId, tool);

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
  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  }) async {
    final metadata = await _readMetadataFile(metadataPath, defaultMetadata);
    final trustedKeys = <String>{
      for (final dir in directories) ...projectMetadataKeys(dir),
    };
    if (trustedKeys.isEmpty) {
      return metadata;
    }

    final existingProjects = metadata['projects'];
    final projects = existingProjects is Map
        ? Map<String, Object?>.from(
            existingProjects.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : <String, Object?>{};

    for (final key in trustedKeys) {
      final existing = projects[key];
      final projectConfig = existing is Map
          ? Map<String, Object?>.from(
              existing.map(
                (entryKey, value) => MapEntry(entryKey.toString(), value),
              ),
            )
          : <String, Object?>{...defaultProjectConfig};
      for (final entry in defaultProjectConfig.entries) {
        projectConfig.putIfAbsent(entry.key, () => entry.value);
      }
      for (final entry in defaultProjectConfig.entries) {
        if (entry.value == true) {
          projectConfig[entry.key] = true;
        }
      }
      projects[key] = projectConfig;
    }
    metadata['projects'] = projects;
    return metadata;
  }

  @override
  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  }) async {
    final trustedKeys = {
      for (final dir in directories) ...projectMetadataKeys(dir),
    };
    if (trustedKeys.isEmpty) return false;

    final metadata = await _readMetadataFile(metadataPath, defaultMetadata);
    final projects = metadata['projects'];
    if (projects is! Map) return false;

    for (final key in trustedKeys) {
      final project = projects[key];
      if (project is! Map) return false;
      if (project['hasTrustDialogAccepted'] != true) return false;
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
    String? projectId,
  }) =>
      _writeSettingsFile(
        path,
        settings,
        memberToolDir: memberToolDir,
        tool: tool,
        teamId: teamId,
        projectId: projectId,
      );

  @override
  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
    String? projectId,
  }) =>
      _extensionProvisioner(teamId: teamId, projectId: projectId)
          .hasEnabledSettingsHooksForTool(tool);

  @override
  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? projectId,
  }) =>
      _extensionProvisioner(teamId: teamId, projectId: projectId).applySettings(
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
      sessionToolDir(scope.teamId, scope.sessionId, tool),
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
    String? projectId,
  }) async {
    warnings.addAll(
      await _extensionProvisioner(teamId: teamId, projectId: projectId)
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
    String? projectId,
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
      projectId: projectId,
    );
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(merged),
    );
  }

  ExtensionProvisioner _extensionProvisioner({
    String? teamId,
    String? projectId,
  }) {
    return ExtensionProvisioner(
      manifests: _extensionManifests ?? builtInExtensionManifests(),
      isEnabled: (id) async => (await _enabledExtensionIds(
        teamId: teamId,
        projectId: projectId,
      )).contains(id),
      detector: _extensionDetector,
      hookProvisionerFor: _hookProvisionerForAsset,
    );
  }

  Future<Set<String>> _enabledExtensionIds({
    String? teamId,
    String? projectId,
  }) async {
    final loader = _loadEnabledExtensionIds;
    if (loader == null) return {};
    return loader(teamId: teamId, projectId: projectId);
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

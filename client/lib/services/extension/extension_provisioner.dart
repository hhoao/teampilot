import '../../models/extension_manifest.dart';
import '../../models/mcp_server.dart';
import '../host/script_file_hook_provisioner.dart';
import 'effect/settings_hook_effect_applier.dart';
import 'extension_detector.dart';

/// Builds a hook-script provisioner for a given `scriptAsset`. Supplied by the
/// caller so asset-specific script loading stays out of this generic engine.
typedef HookProvisionerFactory = ScriptFileHookProvisioner Function(
  String scriptAsset,
);

/// Orchestrates enabled extension manifests: surfaces readiness warnings and
/// applies `settings-hook` effects into a settings map. The seam that replaces
/// the former bespoke rtk logic in `ConfigProfileService`.
class ExtensionProvisioner {
  ExtensionProvisioner({
    required List<ExtensionManifest> manifests,
    required Future<bool> Function(String extensionId) isEnabled,
    HookProvisionerFactory? hookProvisionerFor,
    ExtensionDetector? detector,
    SettingsHookEffectApplier settingsHookApplier =
        const SettingsHookEffectApplier(),
  })  : _manifests = manifests,
        _isEnabled = isEnabled,
        _hookProvisionerFor = hookProvisionerFor,
        _detector = detector ?? ExtensionDetector(),
        _settingsHookApplier = settingsHookApplier;

  final List<ExtensionManifest> _manifests;
  final Future<bool> Function(String extensionId) _isEnabled;
  final HookProvisionerFactory? _hookProvisionerFor;
  final ExtensionDetector _detector;
  final SettingsHookEffectApplier _settingsHookApplier;

  /// Warning codes for enabled-but-unready extensions, mirroring the legacy
  /// `rtk_enabled_*` shape: `<id>_enabled_not_found`,
  /// `<id>_enabled_dependency_missing`, `<id>_enabled_version_too_old`.
  Future<List<String>> collectWarnings() async {
    final out = <String>[];
    for (final manifest in _manifests) {
      if (!await _isEnabled(manifest.id)) continue;
      final probe = await _detector.probe(manifest.detect);
      if (!probe.found) {
        out.add('${manifest.id}_enabled_not_found');
        continue;
      }
      if (probe.missingRequirements.isNotEmpty) {
        out.add('${manifest.id}_enabled_dependency_missing');
        continue;
      }
      if (!probe.satisfiesMinVersion) {
        out.add('${manifest.id}_enabled_version_too_old');
      }
    }
    return out;
  }

  /// Whether any enabled extension has a `settings-hook` for [tool].
  ///
  /// When [tool] is empty, returns true if any enabled extension has a hook.
  Future<bool> hasEnabledSettingsHooksForTool(String tool) async {
    for (final manifest in _manifests) {
      if (!await _isEnabled(manifest.id)) continue;
      for (final effect in manifest.effects) {
        if (effect.kind != 'settings-hook') continue;
        if (_effectAppliesToTool(effect, tool)) return true;
      }
    }
    return false;
  }

  /// Applies every ready, enabled extension's `settings-hook` effects to [base].
  ///
  /// When [tool] is non-empty, only effects whose `appliesTo` includes [tool]
  /// (or lists no targets) are merged.
  Future<Map<String, Object?>> applySettings(
    Map<String, Object?> base,
    String memberToolDir, {
    String tool = '',
  }) async {
    if (memberToolDir.trim().isEmpty) return base;
    var settings = base;
    for (final manifest in _manifests) {
      if (!await _isEnabled(manifest.id)) continue;
      final probe = await _detector.probe(manifest.detect);
      if (!probe.isReady) continue;
      for (final effect in manifest.effects) {
        if (effect.kind != 'settings-hook') continue;
        if (!_effectAppliesToTool(effect, tool)) continue;
        final factory = _hookProvisionerFor;
        if (factory == null) {
          throw StateError(
            'ExtensionProvisioner: settings-hook effect needs a hookProvisionerFor',
          );
        }
        final provisioner = factory(effect.scriptAsset ?? manifest.id);
        final scriptPath = await provisioner.provision(memberToolDir);
        final command = provisioner.commandForPath(scriptPath);
        settings = _settingsHookApplier.mergeIntoSettings(
          base: settings,
          event: effect.hookEvent ?? 'PreToolUse',
          matcher: effect.hookMatcher ?? 'Bash',
          hookCommand: command,
          marker: effect.marker ?? manifest.id,
        );
      }
    }
    return settings;
  }

  /// `McpServer` entries contributed by every ready, enabled extension with an
  /// `mcp-server` effect. Merged into the team MCP snapshot by the caller.
  Future<List<McpServer>> collectMcpContributions() async {
    final out = <McpServer>[];
    for (final manifest in _manifests) {
      if (!await _isEnabled(manifest.id)) continue;
      final probe = await _detector.probe(manifest.detect);
      if (!probe.isReady) continue;
      for (final effect in manifest.effects) {
        if (effect.kind != 'mcp-server') continue;
        final serverMap = effect.mcpServer ?? const <String, Object?>{};
        if (serverMap.isEmpty) continue;
        final name = effect.mcpName?.trim();
        out.add(
          McpServer(
            id: 'ext:${manifest.id}',
            name: (name != null && name.isNotEmpty) ? name : manifest.id,
            server: serverMap,
            enabled: true,
          ),
        );
      }
    }
    return out;
  }

  static bool _effectAppliesToTool(ExtensionEffect effect, String tool) {
    final trimmed = tool.trim();
    if (trimmed.isEmpty) return true;
    if (effect.appliesTo.isEmpty) return true;
    return effect.appliesTo.contains(trimmed);
  }
}

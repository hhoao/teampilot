import '../../models/extension_manifest.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/run/launch_type_contribution.dart';
import '../../models/workspace_folder.dart';
import '../extension/extension_detector.dart';
import 'launch_adapter_protocol.dart';
import 'launch_config_store.dart';
import 'launch_discover.dart';
import 'launch_type_registry.dart';

/// Probes whether an extension's detect requirements are satisfied.
typedef LaunchTypeDetectFn = Future<bool> Function(ExtensionManifest manifest);

/// Resolves the installed extension directory for `${extensionPath}`.
typedef LaunchTypeExtensionPathFn = String Function(String extensionId);

/// Feeds enabled extension `launch-type` effects into [LaunchTypeRegistry].
///
/// Enablement is injected by the caller (same chain as
/// [WorkspaceProjectConfig.effectiveExtensionEnabled] / ExtensionCubit) —
/// this class does not invent a parallel enablement model.
class LaunchTypeRegistrar {
  LaunchTypeRegistrar({
    required List<ExtensionManifest> extensions,
    required LaunchTypeDetectFn detector,
    required LaunchTypeExtensionPathFn extensionPathFor,
  }) : _extensions = extensions,
       _detector = detector,
       _extensionPathFor = extensionPathFor;

  /// Convenience: wrap [ExtensionDetector.probe] as a [LaunchTypeDetectFn].
  factory LaunchTypeRegistrar.withExtensionDetector({
    required List<ExtensionManifest> extensions,
    required ExtensionDetector detector,
    required LaunchTypeExtensionPathFn extensionPathFor,
  }) {
    return LaunchTypeRegistrar(
      extensions: extensions,
      detector: (manifest) async {
        final probe = await detector.probe(manifest.detect);
        return probe.found &&
            probe.satisfiesMinVersion &&
            probe.missingRequirements.isEmpty;
      },
      extensionPathFor: extensionPathFor,
    );
  }

  final List<ExtensionManifest> _extensions;
  final LaunchTypeDetectFn _detector;
  final LaunchTypeExtensionPathFn _extensionPathFor;

  /// Path resolver for [LaunchAdapterClient] `${extensionPath}` expansion.
  ExtensionPathResolver get pathResolver => _extensionPathFor;

  /// Clears extension types and re-registers from the injected enabled list.
  Future<void> rebuild(LaunchTypeRegistry registry) async {
    registry.clearExtensions();

    for (final manifest in _extensions) {
      final detectOk = await _detector(manifest);
      for (final effect in manifest.effects) {
        final contribution = LaunchTypeContribution.fromEffect(
          extensionId: manifest.id,
          effect: effect,
        );
        if (contribution == null) continue;

        final result = registry.registerExtension(contribution);
        if (result.isConflict) continue;

        // v1: only local targets can prove adapter presence; remote → unavailable.
        registry.setAvailability(
          contribution.type,
          targetId: WorkspaceFolder.localTargetId,
          available: detectOk,
        );
      }
    }
  }

  /// Glob-based recommendations for enabled launch types (v1: globs only).
  Future<List<OwnedLaunchConfiguration>> discoverRecommendations({
    required LaunchTypeRegistry registry,
    required List<WorkspaceFolder> folders,
    required LaunchConfigIo io,
    List<OwnedLaunchConfiguration> existing = const [],
  }) {
    return LaunchDiscover(io: io).discover(
      folders: folders,
      registry: registry,
      existing: existing,
    );
  }
}

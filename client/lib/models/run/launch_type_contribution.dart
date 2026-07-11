import 'package:flutter/foundation.dart';

import '../extension_manifest.dart';

/// Adapter process lifecycle declared by a `launch-type` extension effect.
enum LaunchAdapterLifecycle {
  sticky,
  oneshot,
}

/// A registered launch type from a built-in definition or extension effect.
@immutable
class LaunchTypeContribution {
  const LaunchTypeContribution({
    this.extensionId,
    required this.type,
    required this.kinds,
    required this.adapterCommand,
    required this.adapterRuntime,
    required this.lifecycle,
    required this.configurationSchema,
    this.discover,
  });

  /// Null for built-in types such as `process`.
  final String? extensionId;
  final String type;
  final List<String> kinds;
  final String adapterCommand;
  final String adapterRuntime;
  final LaunchAdapterLifecycle lifecycle;
  final Map<String, Object?> configurationSchema;
  final Map<String, Object?>? discover;

  /// Parses a `launch-type` [ExtensionEffect] into a contribution.
  ///
  /// Returns null when the effect is not a launch type or uses an unsupported
  /// adapter runtime (v1: only `workspace`).
  static LaunchTypeContribution? fromEffect({
    required String extensionId,
    required ExtensionEffect effect,
  }) {
    if (effect.kind != 'launch-type') return null;

    final type = effect.launchType?.trim();
    if (type == null || type.isEmpty) return null;

    final adapter = effect.launchAdapter;
    if (adapter == null) return null;

    final runtime = (adapter['runtime'] as String?)?.trim() ?? '';
    if (runtime != 'workspace') return null;

    final command = (adapter['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) return null;

    final lifecycleRaw = (adapter['lifecycle'] as String?)?.trim() ?? 'sticky';
    final lifecycle = switch (lifecycleRaw) {
      'oneshot' => LaunchAdapterLifecycle.oneshot,
      'sticky' => LaunchAdapterLifecycle.sticky,
      _ => LaunchAdapterLifecycle.sticky,
    };

    final schema = effect.launchConfigurationSchema;
    if (schema == null) return null;

    return LaunchTypeContribution(
      extensionId: extensionId,
      type: type,
      kinds: effect.launchKinds ?? const ['run'],
      adapterCommand: command,
      adapterRuntime: runtime,
      lifecycle: lifecycle,
      configurationSchema: Map<String, Object?>.from(schema),
      discover: effect.launchDiscover == null
          ? null
          : Map<String, Object?>.from(effect.launchDiscover!),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchTypeContribution &&
          runtimeType == other.runtimeType &&
          extensionId == other.extensionId &&
          type == other.type &&
          listEquals(kinds, other.kinds) &&
          adapterCommand == other.adapterCommand &&
          adapterRuntime == other.adapterRuntime &&
          lifecycle == other.lifecycle &&
          mapEquals(configurationSchema, other.configurationSchema) &&
          mapEquals(discover, other.discover);

  @override
  int get hashCode => Object.hash(
    extensionId,
    type,
    Object.hashAll(kinds),
    adapterCommand,
    adapterRuntime,
    lifecycle,
    Object.hashAll(configurationSchema.entries),
    discover == null ? null : Object.hashAll(discover!.entries),
  );
}

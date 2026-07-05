import 'package:flutter/foundation.dart';

import 'config_bundle.dart';

/// Project-scoped bindings for a workspace (`project-config.json`).
///
/// Skills, plugins, and MCP ids are stored in [bundle]. Extension overrides
/// map extension id → forced on/off; absent keys follow the global default.
@immutable
class WorkspaceProjectConfig {
  const WorkspaceProjectConfig({
    this.bundle = const ConfigBundle(),
    this.extensionOverrides = const {},
  });

  factory WorkspaceProjectConfig.fromJson(Map<String, Object?> json) {
    return WorkspaceProjectConfig(
      bundle: ConfigBundle.fromJson(json),
      extensionOverrides: _decodeExtensionOverrides(json['extensionOverrides']),
    );
  }

  final ConfigBundle bundle;
  final Map<String, bool> extensionOverrides;

  static Map<String, bool> _decodeExtensionOverrides(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, bool>{};
    for (final entry in raw.entries) {
      final id = entry.key.toString().trim();
      if (id.isEmpty) continue;
      final value = entry.value;
      if (value is bool) {
        out[id] = value;
      }
    }
    return Map.unmodifiable(out);
  }

  WorkspaceProjectConfig copyWith({
    ConfigBundle? bundle,
    Map<String, bool>? extensionOverrides,
  }) {
    return WorkspaceProjectConfig(
      bundle: bundle ?? this.bundle,
      extensionOverrides: extensionOverrides ?? this.extensionOverrides,
    );
  }

  /// Whether [extensionId] is forced on/off for this workspace, or null to
  /// follow the global default.
  bool? extensionOverrideFor(String extensionId) {
    return extensionOverrides[extensionId.trim()];
  }

  bool effectiveExtensionEnabled({
    required String extensionId,
    required Set<String> globalEnabled,
  }) {
    final override = extensionOverrideFor(extensionId);
    if (override != null) return override;
    return globalEnabled.contains(extensionId);
  }

  Map<String, Object?> toJson() {
    return {
      ...bundle.toJson(),
      if (extensionOverrides.isNotEmpty)
        'extensionOverrides': {
          for (final entry in extensionOverrides.entries) entry.key: entry.value,
        },
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceProjectConfig &&
          bundle == other.bundle &&
          mapEquals(extensionOverrides, other.extensionOverrides);

  @override
  int get hashCode => Object.hash(bundle, Object.hashAll(extensionOverrides.entries));
}

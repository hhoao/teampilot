import 'package:flutter/foundation.dart';

/// The shared skills/plugins/mcp enable-lists carried by every
/// [WorkspaceIdentity]. Extensions are tracked separately in
/// ExtensionRepository, keyed by identity id.
@immutable
class ConfigBundle {
  const ConfigBundle({
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
  });

  factory ConfigBundle.fromJson(Map<String, Object?> json) => ConfigBundle(
        skillIds: _decodeIds(json['skillIds']),
        pluginIds: _decodeIds(json['pluginIds']),
        mcpServerIds: _decodeIds(json['mcpServerIds']),
      );

  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpServerIds;

  static List<String> _decodeIds(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  ConfigBundle copyWith({
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
  }) =>
      ConfigBundle(
        skillIds: skillIds ?? this.skillIds,
        pluginIds: pluginIds ?? this.pluginIds,
        mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      );

  Map<String, Object?> toJson() => {
        if (skillIds.isNotEmpty) 'skillIds': skillIds,
        if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
        if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigBundle &&
          listEquals(skillIds, other.skillIds) &&
          listEquals(pluginIds, other.pluginIds) &&
          listEquals(mcpServerIds, other.mcpServerIds);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(skillIds),
        Object.hashAll(pluginIds),
        Object.hashAll(mcpServerIds),
      );
}

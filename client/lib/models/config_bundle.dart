import 'package:flutter/foundation.dart';

/// The shared skills/plugins/mcp/hooks enable-lists carried by every
/// [LaunchProfile]. Extensions are tracked separately in
/// ExtensionRepository, keyed by identity id.
@immutable
class ConfigBundle {
  const ConfigBundle({
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpServerIds = const [],
    this.hookIds = const [],
  });

  factory ConfigBundle.fromJson(Map<String, Object?> json) => ConfigBundle(
    skillIds: _decodeIds(json['skillIds']),
    pluginIds: _decodeIds(json['pluginIds']),
    mcpServerIds: _decodeIds(json['mcpServerIds']),
    hookIds: _decodeIds(json['hookIds']),
  );

  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpServerIds;
  final List<String> hookIds;

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
    List<String>? hookIds,
  }) => ConfigBundle(
    skillIds: skillIds ?? this.skillIds,
    pluginIds: pluginIds ?? this.pluginIds,
    mcpServerIds: mcpServerIds ?? this.mcpServerIds,
    hookIds: hookIds ?? this.hookIds,
  );

  Map<String, Object?> toJson() => {
    if (skillIds.isNotEmpty) 'skillIds': skillIds,
    if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
    if (mcpServerIds.isNotEmpty) 'mcpServerIds': mcpServerIds,
    if (hookIds.isNotEmpty) 'hookIds': hookIds,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigBundle &&
          listEquals(skillIds, other.skillIds) &&
          listEquals(pluginIds, other.pluginIds) &&
          listEquals(mcpServerIds, other.mcpServerIds) &&
          listEquals(hookIds, other.hookIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(skillIds),
    Object.hashAll(pluginIds),
    Object.hashAll(mcpServerIds),
    Object.hashAll(hookIds),
  );
}

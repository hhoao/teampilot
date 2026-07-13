import 'package:flutter/foundation.dart';

import '../workspace_folder.dart';

/// A single entry from a folder's `.teampilot/launch.json` `configurations` array.
@immutable
class LaunchConfiguration {
  const LaunchConfiguration({
    required this.id,
    required this.name,
    required this.type,
    this.request = 'launch',
    this.cwd,
    this.env = const {},
    this.extras = const {},
  });

  final String id;
  final String name;
  final String type;
  final String request;
  final String? cwd;
  final Map<String, String> env;
  final Map<String, Object?> extras;

  static const _knownKeys = {
    'id',
    'name',
    'type',
    'request',
    'cwd',
    'env',
  };

  factory LaunchConfiguration.fromJson(Map<String, Object?> json) {
    final extras = <String, Object?>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) {
        extras[entry.key] = entry.value;
      }
    }

    return LaunchConfiguration(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      request: json['request'] as String? ?? 'launch',
      cwd: json['cwd'] as String?,
      env: _stringMap(json['env']),
      extras: extras,
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (name.isNotEmpty) 'name': name,
      if (type.isNotEmpty) 'type': type,
      if (request != 'launch') 'request': request,
      if (cwd != null) 'cwd': cwd,
      if (env.isNotEmpty) 'env': env,
      ...extras,
    };
  }

  LaunchConfiguration copyWith({
    String? id,
    String? name,
    String? type,
    String? request,
    String? cwd,
    Map<String, String>? env,
    Map<String, Object?>? extras,
  }) {
    return LaunchConfiguration(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      request: request ?? this.request,
      cwd: cwd ?? this.cwd,
      env: env ?? this.env,
      extras: extras ?? this.extras,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchConfiguration &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          request == other.request &&
          cwd == other.cwd &&
          mapEquals(env, other.env) &&
          mapEquals(extras, other.extras);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    request,
    cwd,
    Object.hashAll(env.entries),
    Object.hashAll(extras.entries),
  );
}

/// A configuration tagged with the workspace folder that owns its `launch.json`.
@immutable
class OwnedLaunchConfiguration {
  const OwnedLaunchConfiguration({
    required this.owner,
    required this.configuration,
  });

  final WorkspaceFolder owner;
  final LaunchConfiguration configuration;

  String get configId => configuration.id;

  /// Stable UI selection key: target + folder path + config id.
  String get selectionKey =>
      '${owner.targetId}|${owner.path}|${configuration.id}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OwnedLaunchConfiguration &&
          runtimeType == other.runtimeType &&
          owner == other.owner &&
          configuration == other.configuration;

  @override
  int get hashCode => Object.hash(owner, configuration);
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key != null) entry.key.toString(): entry.value?.toString() ?? '',
  };
}

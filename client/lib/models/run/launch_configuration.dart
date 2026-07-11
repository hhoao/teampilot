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
    this.command,
    this.args = const [],
    this.cwd,
    this.env = const {},
    this.shell,
    this.extras = const {},
  });

  final String id;
  final String name;
  final String type;
  final String request;
  final String? command;
  final List<String> args;
  final String? cwd;
  final Map<String, String> env;
  final bool? shell;
  final Map<String, Object?> extras;

  static const _knownKeys = {
    'id',
    'name',
    'type',
    'request',
    'command',
    'args',
    'cwd',
    'env',
    'shell',
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
      command: json['command'] as String?,
      args: _stringList(json['args']),
      cwd: json['cwd'] as String?,
      env: _stringMap(json['env']),
      shell: json['shell'] as bool?,
      extras: extras,
    );
  }

  Map<String, Object?> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (name.isNotEmpty) 'name': name,
      if (type.isNotEmpty) 'type': type,
      if (request != 'launch') 'request': request,
      if (command != null) 'command': command,
      if (args.isNotEmpty) 'args': args,
      if (cwd != null) 'cwd': cwd,
      if (env.isNotEmpty) 'env': env,
      if (shell != null) 'shell': shell,
      ...extras,
    };
  }

  LaunchConfiguration copyWith({
    String? id,
    String? name,
    String? type,
    String? request,
    String? command,
    List<String>? args,
    String? cwd,
    Map<String, String>? env,
    bool? shell,
    Map<String, Object?>? extras,
  }) {
    return LaunchConfiguration(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      request: request ?? this.request,
      command: command ?? this.command,
      args: args ?? this.args,
      cwd: cwd ?? this.cwd,
      env: env ?? this.env,
      shell: shell ?? this.shell,
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
          command == other.command &&
          listEquals(args, other.args) &&
          cwd == other.cwd &&
          mapEquals(env, other.env) &&
          shell == other.shell &&
          mapEquals(extras, other.extras);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    request,
    command,
    Object.hashAll(args),
    cwd,
    Object.hashAll(env.entries),
    shell,
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

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item != null) item.toString(),
  ];
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key != null) entry.key.toString(): entry.value?.toString() ?? '',
  };
}

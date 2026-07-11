import 'package:flutter/foundation.dart';

import 'launch_configuration.dart';

/// Parsed `.teampilot/launch.json` for one workspace folder.
@immutable
class LaunchConfigDocument {
  const LaunchConfigDocument({
    required this.version,
    this.configurations = const [],
    this.compounds = const [],
  });

  final int version;
  final List<LaunchConfiguration> configurations;
  final List<LaunchCompound> compounds;

  factory LaunchConfigDocument.fromJson(Map<String, Object?> json) {
    return LaunchConfigDocument(
      version: (json['version'] as num?)?.toInt() ?? 1,
      configurations: [
        for (final item in json['configurations'] as List? ?? const [])
          if (item is Map<String, Object?>)
            LaunchConfiguration.fromJson(item),
      ],
      compounds: [
        for (final item in json['compounds'] as List? ?? const [])
          if (item is Map<String, Object?>) LaunchCompound.fromJson(item),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    if (configurations.isNotEmpty)
      'configurations': [for (final c in configurations) c.toJson()],
    if (compounds.isNotEmpty)
      'compounds': [for (final c in compounds) c.toJson()],
  };

  /// Fills missing ids from name slugs and ensures uniqueness within the file.
  LaunchConfigDocument normalized() {
    final usedIds = <String>{};
    final normalizedConfigs = <LaunchConfiguration>[];
    for (final config in configurations) {
      final id = _assignId(
        existingId: config.id,
        name: config.name,
        usedIds: usedIds,
      );
      usedIds.add(id);
      normalizedConfigs.add(
        config.id == id ? config : config.copyWith(id: id),
      );
    }

    final normalizedCompounds = <LaunchCompound>[];
    for (final compound in compounds) {
      final id = _assignId(
        existingId: compound.id,
        name: compound.name,
        usedIds: usedIds,
      );
      usedIds.add(id);
      normalizedCompounds.add(
        compound.id == id ? compound : compound.copyWith(id: id),
      );
    }

    return LaunchConfigDocument(
      version: version,
      configurations: normalizedConfigs,
      compounds: normalizedCompounds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchConfigDocument &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          listEquals(configurations, other.configurations) &&
          listEquals(compounds, other.compounds);

  @override
  int get hashCode =>
      Object.hash(version, Object.hashAll(configurations), Object.hashAll(compounds));
}

/// A compound launch that starts multiple configurations in parallel.
@immutable
class LaunchCompound {
  const LaunchCompound({
    required this.id,
    required this.name,
    this.configurationIds = const [],
  });

  final String id;
  final String name;
  final List<String> configurationIds;

  factory LaunchCompound.fromJson(Map<String, Object?> json) {
    return LaunchCompound(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      configurationIds: [
        for (final item in json['configurations'] as List? ?? const [])
          if (item != null) item.toString(),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    if (id.isNotEmpty) 'id': id,
    if (name.isNotEmpty) 'name': name,
    if (configurationIds.isNotEmpty) 'configurations': configurationIds,
  };

  LaunchCompound copyWith({
    String? id,
    String? name,
    List<String>? configurationIds,
  }) {
    return LaunchCompound(
      id: id ?? this.id,
      name: name ?? this.name,
      configurationIds: configurationIds ?? this.configurationIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchCompound &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          listEquals(configurationIds, other.configurationIds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(configurationIds));
}

String _assignId({
  required String existingId,
  required String name,
  required Set<String> usedIds,
}) {
  final trimmed = existingId.trim();
  if (trimmed.isNotEmpty && !usedIds.contains(trimmed)) {
    return trimmed;
  }

  var base = _slugFromName(name);
  if (base.isEmpty) {
    base = 'config';
  }

  var candidate = base;
  var suffix = 2;
  while (usedIds.contains(candidate)) {
    candidate = '$base-$suffix';
    suffix++;
  }
  return candidate;
}

String _slugFromName(String name) {
  final buffer = StringBuffer();
  var pendingDash = false;
  for (final codeUnit in name.trim().toLowerCase().codeUnits) {
    final isAlphaNumeric =
        (codeUnit >= 97 && codeUnit <= 122) ||
        (codeUnit >= 48 && codeUnit <= 57);
    if (isAlphaNumeric) {
      if (pendingDash) {
        buffer.write('-');
        pendingDash = false;
      }
      buffer.writeCharCode(codeUnit);
    } else {
      pendingDash = buffer.isNotEmpty;
    }
  }
  return buffer.toString();
}

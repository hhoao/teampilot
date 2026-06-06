import 'package:flutter/foundation.dart';

/// How a project avatar is chosen.
@immutable
sealed class ProjectIconRef {
  const ProjectIconRef();

  static const auto = ProjectIconAuto();

  factory ProjectIconRef.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return auto;
    return switch (json['kind']) {
      'preset' => ProjectIconPreset(_readPresetIndex(json['index'])),
      'custom' => _readCustom(json['path']),
      _ => auto,
    };
  }

  Object? toJson() => switch (this) {
    ProjectIconAuto() => null,
    ProjectIconPreset(:final index) => {'kind': 'preset', 'index': index},
    ProjectIconCustom(:final relativePath) => {
      'kind': 'custom',
      'path': relativePath,
    },
  };

  static ProjectIconCustom _readCustom(Object? path) {
    final value = path is String ? path.trim() : '';
    if (value.isEmpty) return const ProjectIconCustom('');
    return ProjectIconCustom(value);
  }

  static int _readPresetIndex(Object? index) {
    if (index is! int) return 0;
    return index < 0 ? 0 : index;
  }
}

@immutable
final class ProjectIconAuto extends ProjectIconRef {
  const ProjectIconAuto();

  @override
  bool operator ==(Object other) => other is ProjectIconAuto;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
final class ProjectIconPreset extends ProjectIconRef {
  const ProjectIconPreset(this.index);

  final int index;

  @override
  bool operator ==(Object other) =>
      other is ProjectIconPreset && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

@immutable
final class ProjectIconCustom extends ProjectIconRef {
  const ProjectIconCustom(this.relativePath);

  final String relativePath;

  bool get isValid => relativePath.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ProjectIconCustom && other.relativePath == relativePath;

  @override
  int get hashCode => relativePath.hashCode;
}

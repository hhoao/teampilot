import 'package:flutter/foundation.dart';

/// How a workspace avatar is chosen.
@immutable
sealed class WorkspaceIconRef {
  const WorkspaceIconRef();

  static const auto = WorkspaceIconAuto();

  factory WorkspaceIconRef.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return auto;
    return switch (json['kind']) {
      'preset' => WorkspaceIconPreset(_readPresetIndex(json['index'])),
      'custom' => _readCustom(json['path']),
      _ => auto,
    };
  }

  Object? toJson() => switch (this) {
    WorkspaceIconAuto() => null,
    WorkspaceIconPreset(:final index) => {'kind': 'preset', 'index': index},
    WorkspaceIconCustom(:final relativePath) => {
      'kind': 'custom',
      'path': relativePath,
    },
  };

  static WorkspaceIconCustom _readCustom(Object? path) {
    final value = path is String ? path.trim() : '';
    if (value.isEmpty) return const WorkspaceIconCustom('');
    return WorkspaceIconCustom(value);
  }

  static int _readPresetIndex(Object? index) {
    if (index is! int) return 0;
    return index < 0 ? 0 : index;
  }
}

@immutable
final class WorkspaceIconAuto extends WorkspaceIconRef {
  const WorkspaceIconAuto();

  @override
  bool operator ==(Object other) => other is WorkspaceIconAuto;

  @override
  int get hashCode => runtimeType.hashCode;
}

@immutable
final class WorkspaceIconPreset extends WorkspaceIconRef {
  const WorkspaceIconPreset(this.index);

  final int index;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceIconPreset && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

@immutable
final class WorkspaceIconCustom extends WorkspaceIconRef {
  const WorkspaceIconCustom(this.relativePath);

  final String relativePath;

  bool get isValid => relativePath.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceIconCustom && other.relativePath == relativePath;

  @override
  int get hashCode => relativePath.hashCode;
}

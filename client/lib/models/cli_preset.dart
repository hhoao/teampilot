import 'package:flutter/foundation.dart';

import 'team_config.dart';

@immutable
class CliPreset {
  const CliPreset({
    required this.id,
    required this.name,
    required this.cli,
    required this.provider,
    required this.model,
    this.effort = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory CliPreset.fromJson(Map<String, Object?> json) {
    return CliPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      cli: CliTool.parse(json['cli']),
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      effort: json['effort'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
  final int createdAt;
  final int updatedAt;

  CliPreset copyWith({
    String? id,
    String? name,
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    int? createdAt,
    int? updatedAt,
  }) {
    return CliPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      cli: cli ?? this.cli,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'cli': cli.value,
      'provider': provider,
      'model': model,
      if (effort.isNotEmpty) 'effort': effort,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CliPreset &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            cli == other.cli &&
            provider == other.provider &&
            model == other.model &&
            effort == other.effort &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, cli, provider, model, effort, createdAt, updatedAt);
}

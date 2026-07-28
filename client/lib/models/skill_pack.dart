import 'package:flutter/foundation.dart';

import 'skill_pack_instruction.dart';

/// Install-once unit: Dockerfile-like [install] instruction list.
@immutable
class SkillPack {
  const SkillPack({
    required this.id,
    required this.name,
    this.description,
    this.labels = const {},
    required this.install,
  });

  final String id;
  final String name;
  final String? description;
  final Map<String, String> labels;
  final List<SkillPackInstruction> install;

  factory SkillPack.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim() ?? '';
    final description = (json['description'] as String?)?.trim();
    final labelsRaw = json['labels'];
    final labels = <String, String>{};
    if (labelsRaw is Map) {
      for (final e in labelsRaw.entries) {
        final key = e.key.toString().trim();
        if (key.isEmpty) continue;
        labels[key] = e.value?.toString() ?? '';
      }
    }
    final installRaw = json['install'];
    if (installRaw is! List || installRaw.isEmpty) {
      throw const FormatException('SkillPack.install must be a non-empty array');
    }
    return SkillPack(
      id: id,
      name: name,
      description: description == null || description.isEmpty ? null : description,
      labels: Map.unmodifiable(labels),
      install: parseSkillPackInstall(installRaw),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (description != null && description!.isNotEmpty) 'description': description,
    if (labels.isNotEmpty) 'labels': labels,
    'install': [
      for (final step in install) _instructionToJson(step),
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is SkillPack &&
      id == other.id &&
      name == other.name &&
      description == other.description &&
      mapEquals(labels, other.labels) &&
      listEquals(install, other.install);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    Object.hashAll(labels.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(install),
  );
}

Map<String, Object?> _instructionToJson(SkillPackInstruction step) {
  return switch (step) {
    FromInstruction(:final owner, :final name, :final branch) => {
      'FROM': '$owner/$name@$branch',
    },
    ScriptInstruction(
      :final url,
      :final id,
      :final primaryDirectory,
      :final alternatives,
      :final optional,
    ) =>
      {
        'SCRIPT': {
          'url': url,
          if (id != null && id.isNotEmpty) 'id': id,
          if (primaryDirectory != null && primaryDirectory.isNotEmpty)
            'primaryDirectory': primaryDirectory,
          if (alternatives.isNotEmpty) 'alternatives': alternatives,
        },
        if (optional) 'optional': true,
      },
    CopyInstruction(:final from, :final to) => {
      'COPY': [from, to],
    },
    SkillsInstruction(:final includeAll, :final include, :final exclude) => {
      'SKILLS': includeAll && exclude.isEmpty
          ? '*'
          : {
              if (includeAll) 'include': '*',
              if (!includeAll) 'include': include,
              if (exclude.isNotEmpty) 'exclude': exclude,
            },
    },
    ShellInstruction(:final wrapper) => {'SHELL': wrapper},
    RunInstruction(:final shell, :final exec, :final optional) => {
      'RUN': shell ?? exec,
      if (optional) 'optional': true,
    },
    WorkdirInstruction(:final path) => {'WORKDIR': path},
    PathInstruction(:final entries) => {
      'PATH': entries.length == 1 ? entries.single : entries,
    },
    EnvInstruction(:final entries) => {'ENV': entries},
  };
}

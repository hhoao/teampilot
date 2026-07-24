import 'package:flutter/foundation.dart';

/// One step in a [SkillInstallRecipe].
@immutable
class SkillInstallStep {
  const SkillInstallStep({
    required this.id,
    required this.uses,
    this.withArgs = const {},
    this.needs = const [],
    this.optional = false,
  });

  final String id;
  final String uses;
  final Map<String, Object?> withArgs;
  final List<String> needs;
  final bool optional;

  factory SkillInstallStep.fromJson(Map<String, Object?> json) {
    final withRaw = json['with'];
    final needsRaw = json['needs'];
    return SkillInstallStep(
      id: (json['id'] as String?)?.trim() ?? '',
      uses: (json['uses'] as String?)?.trim() ?? '',
      withArgs: withRaw is Map
          ? withRaw.map((k, v) => MapEntry(k.toString(), v as Object?))
          : const {},
      needs: needsRaw is List
          ? needsRaw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false)
          : const [],
      optional: json['optional'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'uses': uses,
    if (withArgs.isNotEmpty) 'with': withArgs,
    if (needs.isNotEmpty) 'needs': needs,
    if (optional) 'optional': true,
  };

  @override
  bool operator ==(Object other) =>
      other is SkillInstallStep &&
      id == other.id &&
      uses == other.uses &&
      mapEquals(withArgs, other.withArgs) &&
      listEquals(needs, other.needs) &&
      optional == other.optional;

  @override
  int get hashCode => Object.hash(
    id,
    uses,
    Object.hashAll(withArgs.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(needs),
    optional,
  );
}

/// Declared outputs of a successful recipe run.
@immutable
class SkillInstallExports {
  const SkillInstallExports({
    this.skills = const [],
    this.path = const [],
    this.env = const {},
  });

  final List<String> skills;
  final List<String> path;
  final Map<String, String> env;

  factory SkillInstallExports.fromJson(Map<String, Object?> json) {
    final skillsRaw = json['skills'];
    final pathRaw = json['path'];
    final envRaw = json['env'];
    return SkillInstallExports(
      skills: skillsRaw is List
          ? skillsRaw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false)
          : const [],
      path: pathRaw is List
          ? pathRaw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false)
          : const [],
      env: envRaw is Map
          ? {
              for (final e in envRaw.entries)
                if (e.key.toString().trim().isNotEmpty)
                  e.key.toString(): e.value?.toString() ?? '',
            }
          : const {},
    );
  }

  Map<String, Object?> toJson() => {
    if (skills.isNotEmpty) 'skills': skills,
    if (path.isNotEmpty) 'path': path,
    if (env.isNotEmpty) 'env': env,
  };

  @override
  bool operator ==(Object other) =>
      other is SkillInstallExports &&
      listEquals(skills, other.skills) &&
      listEquals(path, other.path) &&
      mapEquals(env, other.env);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(skills),
    Object.hashAll(path),
    Object.hashAll(env.entries.map((e) => Object.hash(e.key, e.value))),
  );
}

/// Declarative install graph executed by [SkillAcquisitionEngine].
@immutable
class SkillInstallRecipe {
  const SkillInstallRecipe({
    required this.steps,
    this.exports = const SkillInstallExports(),
  });

  final List<SkillInstallStep> steps;
  final SkillInstallExports exports;

  bool get isEmpty => steps.isEmpty;

  factory SkillInstallRecipe.fromJson(Map<String, Object?> json) {
    final stepsRaw = json['steps'];
    final exportsRaw = json['exports'];
    return SkillInstallRecipe(
      steps: stepsRaw is List
          ? stepsRaw
                .whereType<Map>()
                .map((e) => SkillInstallStep.fromJson(e.cast<String, Object?>()))
                .where((s) => s.id.isNotEmpty && s.uses.isNotEmpty)
                .toList(growable: false)
          : const [],
      exports: exportsRaw is Map
          ? SkillInstallExports.fromJson(exportsRaw.cast<String, Object?>())
          : const SkillInstallExports(),
    );
  }

  Map<String, Object?> toJson() => {
    'steps': [for (final s in steps) s.toJson()],
    if (exports.skills.isNotEmpty ||
        exports.path.isNotEmpty ||
        exports.env.isNotEmpty)
      'exports': exports.toJson(),
  };

  /// Repo field sugar: sync + install one directory as [skillId].
  factory SkillInstallRecipe.singleGitDir({
    required String owner,
    required String name,
    required String branch,
    required String directory,
    required String skillId,
    String? skillName,
  }) => SkillInstallRecipe(
    steps: [
      SkillInstallStep(
        id: 'sync',
        uses: 'git.sync',
        withArgs: {
          'owner': owner,
          'name': name,
          'branch': branch,
        },
      ),
      SkillInstallStep(
        id: 'install',
        uses: 'skill.install-dir',
        needs: const ['sync'],
        withArgs: {
          'directory': directory,
          'id': skillId,
          if (skillName != null && skillName.isNotEmpty) 'name': skillName,
        },
      ),
    ],
    exports: SkillInstallExports(skills: [skillId]),
  );

  /// Opaque HTTPS installer sugar.
  factory SkillInstallRecipe.scriptUrl({
    required String url,
    required String skillId,
    String? primaryDirectory,
    List<String> alternatives = const [],
  }) => SkillInstallRecipe(
    steps: [
      SkillInstallStep(
        id: 'script',
        uses: 'script.run',
        withArgs: {
          'package': url,
          'id': skillId,
          if (primaryDirectory != null && primaryDirectory.isNotEmpty)
            'primaryDirectory': primaryDirectory,
          if (alternatives.isNotEmpty) 'alternatives': alternatives,
        },
      ),
    ],
    exports: SkillInstallExports(skills: [skillId]),
  );

  /// Stable order: Kahn-style; throws [StateError] on cycles / missing needs.
  List<SkillInstallStep> sortedSteps() {
    if (steps.isEmpty) return const [];
    final byId = <String, SkillInstallStep>{
      for (final s in steps) s.id: s,
    };
    if (byId.length != steps.length) {
      throw StateError('Duplicate step ids in skill install recipe');
    }
    final indegree = <String, int>{for (final s in steps) s.id: 0};
    final edges = <String, List<String>>{for (final s in steps) s.id: []};
    for (final s in steps) {
      for (final n in s.needs) {
        if (!byId.containsKey(n)) {
          throw StateError('Step ${s.id} needs unknown step $n');
        }
        edges[n]!.add(s.id);
        indegree[s.id] = (indegree[s.id] ?? 0) + 1;
      }
    }
    final queue = [
      for (final s in steps)
        if ((indegree[s.id] ?? 0) == 0) s.id,
    ];
    final out = <SkillInstallStep>[];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      out.add(byId[id]!);
      for (final next in edges[id]!) {
        final d = (indegree[next] ?? 0) - 1;
        indegree[next] = d;
        if (d == 0) queue.add(next);
      }
    }
    if (out.length != steps.length) {
      throw StateError('Cycle in skill install recipe needs');
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is SkillInstallRecipe &&
      listEquals(steps, other.steps) &&
      exports == other.exports;

  @override
  int get hashCode => Object.hash(Object.hashAll(steps), exports);
}

/// Stable script skill id from package URL: `script:<host>/<path-basename>`.
String skillScriptIdFromPackageUrl(String? package) {
  if (package == null || package.trim().isEmpty) {
    return 'script:unknown';
  }
  final uri = Uri.tryParse(package.trim());
  if (uri == null || uri.host.isEmpty) {
    return 'script:unknown';
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final basename = segments.isEmpty ? 'unknown' : segments.last;
  return 'script:${uri.host}/$basename';
}

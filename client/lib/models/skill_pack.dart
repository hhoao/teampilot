import 'package:flutter/foundation.dart';

import 'skill_install_recipe.dart';

/// One skill published inside a [SkillPack].
@immutable
class SkillPackEntry {
  const SkillPackEntry({
    required this.id,
    required this.directory,
    required this.name,
  });

  final String id;
  final String directory;
  final String name;

  factory SkillPackEntry.fromJson(Map<String, Object?> json) => SkillPackEntry(
    id: (json['id'] as String?)?.trim() ?? '',
    directory: (json['directory'] as String?)?.trim() ?? '',
    name: (json['name'] as String?)?.trim() ?? '',
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'directory': directory,
    'name': name,
  };
}

/// Install-once unit: recipe graph + skill catalog.
@immutable
class SkillPack {
  const SkillPack({
    required this.id,
    required this.name,
    required this.repoOwner,
    required this.repoName,
    required this.repoBranch,
    required this.recipe,
    required this.skills,
  });

  final String id;
  final String name;
  final String repoOwner;
  final String repoName;
  final String repoBranch;
  final SkillInstallRecipe recipe;
  final List<SkillPackEntry> skills;

  factory SkillPack.fromJson(Map<String, Object?> json) {
    final recipeRaw = json['recipe'];
    final skillsRaw = json['skills'];
    final owner = (json['repoOwner'] as String?)?.trim() ?? '';
    final repoName = (json['repoName'] as String?)?.trim() ?? '';
    final branch = (json['repoBranch'] as String?)?.trim() ?? 'main';
    final skills = skillsRaw is List
        ? skillsRaw
              .whereType<Map>()
              .map((e) => SkillPackEntry.fromJson(e.cast<String, Object?>()))
              .where((e) => e.id.isNotEmpty && e.directory.isNotEmpty)
              .toList(growable: false)
        : const <SkillPackEntry>[];
    final recipe = recipeRaw is Map
        ? SkillInstallRecipe.fromJson(recipeRaw.cast<String, Object?>())
        : _defaultPackRecipe(
            owner: owner,
            name: repoName,
            branch: branch,
            skillIds: [for (final s in skills) s.id],
          );
    return SkillPack(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      repoOwner: owner,
      repoName: repoName,
      repoBranch: branch,
      recipe: recipe,
      skills: skills,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'repoOwner': repoOwner,
    'repoName': repoName,
    'repoBranch': repoBranch,
    'recipe': recipe.toJson(),
    'skills': [for (final s in skills) s.toJson()],
  };

  SkillPackEntry? entryById(String skillId) {
    for (final s in skills) {
      if (s.id == skillId) return s;
    }
    return null;
  }

  static SkillInstallRecipe _defaultPackRecipe({
    required String owner,
    required String name,
    required String branch,
    required List<String> skillIds,
  }) => SkillInstallRecipe(
    steps: [
      SkillInstallStep(
        id: 'sync',
        uses: 'git.sync',
        withArgs: {'owner': owner, 'name': name, 'branch': branch},
      ),
      const SkillInstallStep(
        id: 'skills',
        uses: 'skill.register-pack',
        needs: ['sync'],
      ),
    ],
    exports: SkillInstallExports(skills: skillIds),
  );
}

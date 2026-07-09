import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import 'bundle_provenance_lookup.dart';

/// Outcome of mapping a local [DiscoverableMember] for Hub publish.
sealed class ExpertPublishMapResult {
  const ExpertPublishMapResult();
}

final class PublishReadyExpert extends ExpertPublishMapResult {
  const PublishReadyExpert(this.member);
  final DiscoverableMember member;
}

final class PublishBlockedExpert extends ExpertPublishMapResult {
  const PublishBlockedExpert(this.reasons);
  final List<String> reasons;
}

/// Sanitizes a local [DiscoverableMember] into registry-oriented JSON shape.
class ExpertPublishMapper {
  const ExpertPublishMapper._();

  /// Maps [member] for publish.
  ///
  /// When [skillIds] is provided, resolves them via [lookup] (same portability
  /// rules as team publish). Otherwise keeps only already-portable
  /// [DiscoverableMember.skillDeps] (those with non-empty repo fields).
  static ExpertPublishMapResult map({
    required DiscoverableMember member,
    required BundleProvenanceLookup lookup,
    required String key,
    List<String>? skillIds,
    String? author,
    String? category,
    int? updatedAt,
  }) {
    final reasons = <String>[];
    late final List<SkillDependencyRef> skillDeps;

    if (skillIds != null) {
      final deps = lookup.resolve(
        skillIds: skillIds,
        pluginIds: const [],
        mcpServerIds: const [],
      );
      for (final id in deps.nonPortableIds) {
        reasons.add('Non-portable bundle dependency: $id');
      }
      skillDeps = deps.skillDeps;
    } else {
      skillDeps = [
        for (final dep in member.skillDeps)
          if (_isPortableSkillDep(dep)) dep,
      ];
      // If the member carried skillDeps that aren't portable, block.
      if (skillDeps.length != member.skillDeps.length) {
        for (final dep in member.skillDeps) {
          if (!_isPortableSkillDep(dep)) {
            reasons.add(
              'Non-portable skill dependency: ${dep.repoOwner}/${dep.repoName}:${dep.directory}',
            );
          }
        }
      }
    }

    if (reasons.isNotEmpty) {
      return PublishBlockedExpert(reasons);
    }

    return PublishReadyExpert(
      DiscoverableMember(
        key: key,
        name: member.name,
        description: member.description,
        category: category ?? member.category,
        author: author ?? member.author,
        updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        tags: member.tags,
        member: member.member,
        skillDeps: skillDeps,
        source: ExpertMemberSource.registry,
        originTeamKey: null,
      ),
    );
  }
}

bool _isPortableSkillDep(SkillDependencyRef dep) {
  return dep.repoOwner.trim().isNotEmpty &&
      dep.repoName.trim().isNotEmpty &&
      dep.directory.trim().isNotEmpty;
}

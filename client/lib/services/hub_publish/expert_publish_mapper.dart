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
  /// When [skillIds] / [pluginIds] / [mcpServerIds] are provided, resolves them
  /// via [lookup] (same portability rules as team publish). Otherwise keeps
  /// only already-portable deps on [member].
  static ExpertPublishMapResult map({
    required DiscoverableMember member,
    required BundleProvenanceLookup lookup,
    required String key,
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
    String? author,
    String? category,
    int? updatedAt,
  }) {
    final reasons = <String>[];
    late final List<SkillDependencyRef> skillDeps;
    late final List<PluginDependencyRef> pluginDeps;
    late final List<McpDependencyRef> mcpDeps;

    final resolveFromIds =
        skillIds != null || pluginIds != null || mcpServerIds != null;
    if (resolveFromIds) {
      final deps = lookup.resolve(
        skillIds: skillIds ?? const [],
        pluginIds: pluginIds ?? const [],
        mcpServerIds: mcpServerIds ?? const [],
      );
      for (final id in deps.nonPortableIds) {
        reasons.add('Non-portable bundle dependency: $id');
      }
      skillDeps = deps.skillDeps;
      pluginDeps = deps.pluginDeps;
      mcpDeps = deps.mcpDeps;
    } else {
      skillDeps = [
        for (final dep in member.skillDeps)
          if (_isPortableSkillDep(dep)) dep,
      ];
      pluginDeps = [
        for (final dep in member.pluginDeps)
          if (_isPortablePluginDep(dep)) dep,
      ];
      mcpDeps = [
        for (final dep in member.mcpDeps)
          if (_isPortableMcpDep(dep)) dep,
      ];
      if (skillDeps.length != member.skillDeps.length) {
        for (final dep in member.skillDeps) {
          if (!_isPortableSkillDep(dep)) {
            reasons.add(
              'Non-portable skill dependency: ${dep.repoOwner}/${dep.repoName}:${dep.directory}',
            );
          }
        }
      }
      if (pluginDeps.length != member.pluginDeps.length) {
        for (final dep in member.pluginDeps) {
          if (!_isPortablePluginDep(dep)) {
            reasons.add(
              'Non-portable plugin dependency: ${dep.marketplaceOwner}/${dep.marketplaceName}/${dep.entryName}',
            );
          }
        }
      }
      if (mcpDeps.length != member.mcpDeps.length) {
        for (final dep in member.mcpDeps) {
          if (!_isPortableMcpDep(dep)) {
            reasons.add('Non-portable MCP dependency: ${dep.id}');
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
        pluginDeps: pluginDeps,
        mcpDeps: mcpDeps,
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

bool _isPortablePluginDep(PluginDependencyRef dep) {
  return dep.marketplaceOwner.trim().isNotEmpty &&
      dep.marketplaceName.trim().isNotEmpty &&
      dep.entryName.trim().isNotEmpty;
}

bool _isPortableMcpDep(McpDependencyRef dep) {
  return dep.id.trim().isNotEmpty && dep.server.isNotEmpty;
}

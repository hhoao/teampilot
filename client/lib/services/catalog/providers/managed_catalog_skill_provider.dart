import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../resource/contribution/resource_origin.dart';
import '../../resource/providers/skill_contribution_provider.dart';

/// Always-on managed skill that teaches agents to use the teampilot catalog MCP.
///
/// Not part of the user `skills/installed` manifest. Tests pass an explicit
/// [sourceDirectory]; production resolves the shipped SKILL.md parent.
final class ManagedCatalogSkillProvider implements SkillContributionProvider {
  ManagedCatalogSkillProvider({String? sourceDirectory})
    : sourceDirectory =
          sourceDirectory ?? resolveShippedCatalogSkillDirectory();

  static const skillId = 'teampilot-catalog';

  static const shippedRelativePath =
      'lib/services/catalog/managed_skills/teampilot-catalog';

  final String sourceDirectory;

  @override
  String get providerId => skillId;

  @override
  FutureOr<Iterable<SkillContribution>> provide(SkillProviderContext context) {
    return [
      SkillContribution(
        id: skillId,
        invocationName: skillId,
        artifact: SkillDirectoryArtifact(sourceDirectory),
        origin: const ContributionOrigin(
          providerId: skillId,
          kind: ResourceOriginKind.managed,
          sourceId: skillId,
        ),
      ),
    ];
  }
}

/// Parent directory of the shipped `SKILL.md` when it exists on disk.
String resolveShippedCatalogSkillDirectory() {
  for (final root in _candidatePackageRoots()) {
    final dir = p.normalize(
      p.join(root, ManagedCatalogSkillProvider.shippedRelativePath),
    );
    if (File(p.join(dir, 'SKILL.md')).existsSync()) return dir;
  }
  return p.normalize(
    p.join(
      Directory.current.path,
      ManagedCatalogSkillProvider.shippedRelativePath,
    ),
  );
}

Iterable<String> _candidatePackageRoots() sync* {
  var dir = Directory.current.path;
  yield dir;
  yield p.join(dir, 'client');
  final parent = p.dirname(dir);
  if (parent != dir) {
    yield parent;
    yield p.join(parent, 'client');
  }
}

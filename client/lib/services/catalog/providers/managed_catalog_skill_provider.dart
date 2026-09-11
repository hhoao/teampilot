import 'package:path/path.dart' as p;

import '../../resource/contribution/resource_origin.dart';
import '../../resource/providers/skill_contribution_provider.dart';
import '../../storage/home_storage.dart';
import 'teampilot_catalog_skill_md.dart';

/// Always-on managed skill that teaches agents to use the teampilot catalog MCP.
///
/// Not part of the user `skills/installed` manifest. Tests may pass an explicit
/// [sourceDirectory]; production writes `SKILL.md` onto the session filesystem.
final class ManagedCatalogSkillProvider implements SkillContributionProvider {
  ManagedCatalogSkillProvider({
    required this.storage,
    this.sourceDirectory,
  });

  static const skillId = 'teampilot-catalog';

  /// Home control-plane storage backing the managed-skill directory when no
  /// session filesystem is available.
  final HomeStorage storage;

  /// When set, [provide] returns this directory without writing.
  final String? sourceDirectory;

  @override
  String get providerId => skillId;

  @override
  Future<Iterable<SkillContribution>> provide(
    SkillProviderContext context,
  ) async {
    final directory = sourceDirectory ?? await _writeManagedSkill(context);
    return [
      SkillContribution(
        id: skillId,
        invocationName: skillId,
        artifact: SkillDirectoryArtifact(directory),
        origin: const ContributionOrigin(
          providerId: skillId,
          kind: ResourceOriginKind.managed,
          sourceId: skillId,
        ),
      ),
    ];
  }

  Future<String> _writeManagedSkill(SkillProviderContext context) async {
    final fs = context.filesystem ?? storage.fs;
    final dest = _managedDirectory(fs.pathContext, context);
    await fs.ensureDir(dest);
    await fs.writeString(
      fs.pathContext.join(dest, 'SKILL.md'),
      teampilotCatalogSkillMd,
    );
    return dest;
  }

  String _managedDirectory(p.Context path, SkillProviderContext context) {
    final target = context.targetConfigDir?.trim();
    if (target != null && target.isNotEmpty) {
      return path.join(target, '.teampilot-managed', skillId);
    }
    return path.join(storage.appDataRoot, '.teampilot-managed', skillId);
  }
}

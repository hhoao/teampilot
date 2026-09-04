import 'dart:io';

import 'package:path/path.dart' as p;

import '../../resource/contribution/resource_origin.dart';
import '../../resource/providers/skill_contribution_provider.dart';
import '../../storage/app_storage.dart';
import 'team_builder_skill_md.dart';

/// Materializes the app-owned Team Builder skill into builder sessions only.
///
/// The provider is injected through [SessionResourceProviderResolver] for
/// `SessionPurpose.teamGeneration` sessions; normal sessions never see it.
/// Tests may pass an explicit [sourceDirectory] to skip writing.
final class ManagedTeamBuilderSkillProvider implements SkillContributionProvider {
  ManagedTeamBuilderSkillProvider({this.sourceDirectory});

  static const skillId = 'team-builder';

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

  /// Read-side lookup used by resource-isolation tests and diagnostics.
  Future<_ManagedBuilderSkillResource?> resolve(String skillIdOrName) async {
    if (skillIdOrName != skillId) return null;
    return _ManagedBuilderSkillResource(content: teamBuilderSkillMd);
  }

  Future<String> _writeManagedSkill(SkillProviderContext context) async {
    final fs = context.filesystem ?? AppStorage.fs;
    final path = fs.pathContext;
    final target = context.targetConfigDir?.trim();
    final String dest;
    if (target != null && target.isNotEmpty) {
      dest = path.join(target, '.teampilot-managed', skillId);
    } else {
      final root = AppStorage.isInstalled
          ? AppStorage.appDataRoot
          : Directory.systemTemp.path;
      dest = p.join(root, '.teampilot-managed', skillId);
    }
    await fs.ensureDir(dest);
    await fs.writeString(path.join(dest, 'SKILL.md'), teamBuilderSkillMd);
    return dest;
  }
}

final class _ManagedBuilderSkillResource {
  const _ManagedBuilderSkillResource({required this.content});

  final String content;
}

import '../../../io/filesystem.dart';
import '../cli_capability.dart';
import '../../../resource/providers/skill_contribution_provider.dart';
import '../../../resource/resource_kind.dart';
import '../../../resource/resource_materializer.dart';
import '../../../resource/skill_link_name.dart';

/// How a resource kind is represented inside a CLI's CONFIG_DIR.
enum ResourceRepresentation { linkedDirectory, mergedJsonEntry }

/// SkillHub contract: how skills land in a CLI's CONFIG_DIR and how they are
/// invoked in prompt text. Contains NO provisioning logic — the shared
/// materializer does the work; this just describes the target shape.
abstract interface class SkillCapability implements CliCapability {
  /// Subdirectory (relative to the CONFIG_DIR) where skill entries live
  /// (e.g. 'skills', 'skill', 'skills-cursor').
  String get skillsSubdir;

  /// How skills are represented inside the CLI's CONFIG_DIR.
  ResourceRepresentation get skillsRepresentation;

  /// The character that prefixes a skill invocation (`/` for Claude, `$` for
  /// Codex). Also opens the compose skill menu alongside `/`.
  String get skillInvocationPrefix;

  /// Renders the prompt text that invokes [skillName]. [namespace] is the
  /// plugin name when the skill ships inside a plugin bundle.
  String skillInvocationText(String skillName, {String? namespace});

  /// Materializes already-assembled neutral skill artifacts into this CLI's
  /// target directory. Catalog and scope resolution do not belong here.
  Future<MaterializeResult> materializeSkills({
    required Filesystem fs,
    required String configDir,
    required Iterable<SkillContribution> contributions,
    ResourceMaterializer? materializer,
  });
}

/// Shared target-side implementation for linked-directory skill CLIs.
///
/// The capability owns only target naming and directory layout. Providers and
/// assemblers have already selected the contributions before this is called.
mixin SkillCapabilityMaterializationMixin {
  String get skillsSubdir;

  Future<MaterializeResult> materializeSkills({
    required Filesystem fs,
    required String configDir,
    required Iterable<SkillContribution> contributions,
    ResourceMaterializer? materializer,
  }) {
    final ordered = List<SkillContribution>.of(contributions);
    final usedNames = <String>{};
    final desired = <ResourceRef>[];
    for (final contribution in ordered) {
      final artifact = contribution.artifact;
      if (artifact is! SkillDirectoryArtifact) continue;

      var linkName = targetSafeSkillLinkName(
        contribution.invocationName,
        namespace: contribution.namespace,
      );
      if (!usedNames.add(linkName)) {
        var suffix = 2;
        final base = linkName;
        while (!usedNames.add(linkName)) {
          linkName = '$base--$suffix';
          suffix++;
        }
      }
      desired.add(
        ResourceRef(
          id: contribution.id,
          linkName: linkName,
          sourceDir: artifact.sourceDirectory,
        ),
      );
    }

    return (materializer ?? ResourceMaterializer(fs: fs)).reconcile(
      kindDir: fs.pathContext.join(configDir, skillsSubdir),
      desired: desired,
    );
  }
}

/// Default: Claude-style `/skill-name` invocation, no namespace.
///
/// [leadingSeparator] is prepended before the prefix when a CLI only
/// recognizes a slash command after whitespace (opencode) — inserting
/// ` /skill-name` keeps the `/` from gluing to the preceding text.
class DefaultSkillInvocationSyntaxCapability {
  const DefaultSkillInvocationSyntaxCapability({this.leadingSeparator = ''});

  final String leadingSeparator;

  String get skillInvocationPrefix => '/';

  String skillInvocationText(String skillName, {String? namespace}) =>
      '$leadingSeparator/${targetSafeSkillLinkName(skillName, namespace: namespace)}';
}

import 'dart:async';

import '../../../models/team_config.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../../io/filesystem.dart';
import '../contribution/resource_origin.dart';

/// Focused inputs needed by skill providers.
class SkillProviderContext {
  const SkillProviderContext({
    required this.cli,
    this.scope,
    this.filesystem,
    this.targetConfigDir,
  });

  final CliTool cli;
  final LaunchProfileScope? scope;
  final Filesystem? filesystem;
  final String? targetConfigDir;
}

/// Neutral source artifact for a skill contribution.
sealed class SkillArtifact {
  const SkillArtifact();
}

final class SkillDirectoryArtifact extends SkillArtifact {
  const SkillDirectoryArtifact(this.sourceDirectory);

  final String sourceDirectory;
}

/// A target-neutral skill contribution.
class SkillContribution {
  const SkillContribution({
    required this.id,
    required this.invocationName,
    required this.origin,
    this.namespace,
    this.artifact,
  });

  final String id;
  final String invocationName;
  final String? namespace;
  final SkillArtifact? artifact;
  final ContributionOrigin origin;
}

/// Supplies skill contributions without writing target configuration.
abstract interface class SkillContributionProvider {
  String get providerId;

  FutureOr<Iterable<SkillContribution>> provide(SkillProviderContext context);
}

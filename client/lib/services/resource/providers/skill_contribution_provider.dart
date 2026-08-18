import 'dart:async';

import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import '../resource_scope.dart';

/// Focused inputs needed by skill providers.
class SkillProviderContext {
  const SkillProviderContext({
    required this.cli,
    this.scope,
    this.filesystem,
    this.targetConfigDir,
    this.sourceId,
  });

  final CliTool cli;
  final ResourceScope? scope;
  final Filesystem? filesystem;
  final String? targetConfigDir;
  final String? sourceId;
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

/// Optional diagnostics emitted by a provider while it filters its source.
///
/// The base provider contract intentionally remains an iterable so existing
/// providers stay source-compatible. Assemblers collect this optional
/// projection immediately after the single provider invocation.
abstract interface class SkillContributionProviderDiagnostics {
  List<ResourceAssemblyDiagnostic> get diagnostics;
}

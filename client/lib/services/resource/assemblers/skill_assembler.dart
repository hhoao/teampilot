import 'dart:async';

import '../../../models/team_config.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_assembly_result.dart';
import '../contribution/resource_origin.dart';
import '../providers/skill_contribution_provider.dart';

/// Assembles target-neutral skills in deterministic provider order.
final class SkillAssembler {
  const SkillAssembler();

  Future<SkillAssemblyResult> assemble({
    required SkillProviderContext context,
    required Iterable<SkillContributionProvider> providers,
  }) async {
    final orderedProviders = List<SkillContributionProvider>.of(providers);
    final provided = await Future.wait<_ProvidedSkills>([
      for (final provider in orderedProviders) _provide(provider, context),
    ]);

    final skills = <SkillContribution>[];
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final seenIds = <String, SkillContribution>{};
    final seenInvocations = <String, SkillContribution>{};

    for (final batch in provided) {
      diagnostics.addAll(batch.diagnostics);
      for (final contribution in batch.contributions) {
        _validate(contribution, context.cli);

        final previous = seenIds[contribution.id];
        if (previous != null) {
          diagnostics.add(
            _warning(
              cli: context.cli,
              contribution: contribution,
              message:
                  'Duplicate skill stable id ${contribution.id}; retained '
                  'earlier ${_originLabel(previous.origin)} over '
                  '${_originLabel(contribution.origin)}.',
            ),
          );
          continue;
        }

        if (contribution.artifact == null) {
          diagnostics.add(
            _warning(
              cli: context.cli,
              contribution: contribution,
              message:
                  'Skill ${contribution.id} has no materialization artifact '
                  'and was discarded.',
            ),
          );
          continue;
        }

        final invocationKey = _invocationKey(contribution);
        final invocationPrevious = seenInvocations[invocationKey];
        if (invocationPrevious != null &&
            invocationPrevious.origin.kind == contribution.origin.kind) {
          diagnostics.add(
            _warning(
              cli: context.cli,
              contribution: contribution,
              message:
                  'Skill invocation/name conflict for '
                  '${contribution.namespace ?? '<global>'}/'
                  '${contribution.invocationName}; retained earlier '
                  '${_originLabel(invocationPrevious.origin)} over '
                  '${_originLabel(contribution.origin)}.',
            ),
          );
          continue;
        }

        seenIds[contribution.id] = contribution;
        seenInvocations[invocationKey] = contribution;
        skills.add(contribution);
      }
    }

    return SkillAssemblyResult(
      skills: skills,
      assembly: ResourceAssemblyResult(diagnostics: diagnostics),
    );
  }

  Future<_ProvidedSkills> _provide(
    SkillContributionProvider provider,
    SkillProviderContext context,
  ) async {
    try {
      final contributions = List<SkillContribution>.unmodifiable(
        await provider.provide(context),
      );
      final diagnostics = <ResourceAssemblyDiagnostic>[];
      if (provider is SkillContributionProviderDiagnostics) {
        diagnostics.addAll(
          (provider as SkillContributionProviderDiagnostics).diagnostics,
        );
      }
      return _ProvidedSkills(
        contributions: contributions,
        diagnostics: List.unmodifiable(diagnostics),
      );
    } on Object catch (error, stackTrace) {
      throw ResourceAssemblyException([
        ResourceAssemblyError.provider(
          resourceKind: ResourceContributionKind.skill,
          cli: context.cli,
          providerId: provider.providerId,
          sourceId: context.sourceId ?? provider.providerId,
          message: 'Skill contribution provider failed: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      ]);
    }
  }

  void _validate(SkillContribution contribution, CliTool cli) {
    if (contribution.id.trim().isEmpty) {
      throw ResourceAssemblyException([
        ResourceAssemblyError.provider(
          resourceKind: ResourceContributionKind.skill,
          cli: cli,
          providerId: contribution.origin.providerId,
          sourceId: contribution.origin.sourceId,
          message: 'Skill contribution id must not be empty.',
        ),
      ]);
    }
    if (contribution.invocationName.trim().isEmpty) {
      throw ResourceAssemblyException([
        ResourceAssemblyError.provider(
          resourceKind: ResourceContributionKind.skill,
          cli: cli,
          providerId: contribution.origin.providerId,
          sourceId: contribution.origin.sourceId,
          message: 'Skill invocation name must not be empty.',
        ),
      ]);
    }
  }

  ResourceAssemblyDiagnostic _warning({
    required CliTool cli,
    required SkillContribution contribution,
    required String message,
  }) => ResourceAssemblyDiagnostic(
    severity: ResourceAssemblyDiagnosticSeverity.warning,
    resourceKind: ResourceContributionKind.skill,
    cli: cli,
    providerId: contribution.origin.providerId,
    sourceId: contribution.origin.sourceId,
    message: message,
  );

  String _invocationKey(SkillContribution contribution) =>
      '${contribution.namespace ?? '<global>'}\u0000${contribution.invocationName}';

  String _originLabel(ContributionOrigin origin) =>
      '${origin.providerId}/${origin.sourceId ?? '<none>'}';
}

final class _ProvidedSkills {
  const _ProvidedSkills({
    required this.contributions,
    required this.diagnostics,
  });

  final List<SkillContribution> contributions;
  final List<ResourceAssemblyDiagnostic> diagnostics;
}

/// Result of skill assembly plus its shared diagnostic projection.
final class SkillAssemblyResult {
  SkillAssemblyResult({
    required Iterable<SkillContribution> skills,
    required this.assembly,
  }) : skills = List.unmodifiable(skills);

  final List<SkillContribution> skills;
  final ResourceAssemblyResult assembly;

  List<ResourceAssemblyDiagnostic> get diagnostics => assembly.diagnostics;
  List<ResourceAssemblyDiagnostic> get warnings => assembly.warnings;
  List<ResourceAssemblyDiagnostic> get errors => assembly.errors;
}

import 'dart:async';

import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/prompt_capability.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_assembly_result.dart';
import '../contribution/resource_origin.dart';
import '../providers/prompt_contribution_provider.dart';

/// Assembles target-neutral prompt sections in deterministic provider order.
final class PromptAssembler {
  const PromptAssembler();

  Future<PromptAssemblyResult> assemble({
    required PromptProviderContext context,
    required Iterable<PromptContributionProvider> providers,
  }) async {
    final orderedProviders = List<PromptContributionProvider>.of(providers);
    final provided = await Future.wait<Iterable<PromptContribution>>([
      for (final provider in orderedProviders) _provide(provider, context),
    ]);

    final sections = <_PromptSectionBuilder>[];
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    for (
      var providerIndex = 0;
      providerIndex < provided.length;
      providerIndex++
    ) {
      for (final contribution in provided[providerIndex]) {
        _validateId(contribution, context.cli);
        _merge(
          sections: sections,
          diagnostics: diagnostics,
          contribution: contribution,
          cli: context.cli,
        );
      }
    }

    final document = PromptDocument([
      for (final section in sections) section.build(),
    ]);
    return PromptAssemblyResult(
      document: document,
      assembly: ResourceAssemblyResult(diagnostics: diagnostics),
    );
  }

  Future<Iterable<PromptContribution>> _provide(
    PromptContributionProvider provider,
    PromptProviderContext context,
  ) async {
    try {
      return await provider.provide(context);
    } on Object catch (error, stackTrace) {
      throw ResourceAssemblyException([
        ResourceAssemblyError.provider(
          resourceKind: ResourceContributionKind.prompt,
          cli: context.cli,
          providerId: provider.providerId,
          sourceId: context.sourceId ?? provider.providerId,
          message: 'Prompt contribution provider failed: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      ]);
    }
  }

  void _validateId(PromptContribution contribution, CliTool cli) {
    if (contribution.id.trim().isNotEmpty) return;
    throw ResourceAssemblyException([
      ResourceAssemblyError.provider(
        resourceKind: ResourceContributionKind.prompt,
        cli: cli,
        providerId: contribution.origin.providerId,
        sourceId: contribution.origin.sourceId,
        message: 'Prompt contribution id must not be empty.',
      ),
    ]);
  }

  void _merge({
    required List<_PromptSectionBuilder> sections,
    required List<ResourceAssemblyDiagnostic> diagnostics,
    required PromptContribution contribution,
    required CliTool cli,
  }) {
    final role = contribution.mergeRole;
    if (role == PromptMergeRole.append) {
      sections.add(_PromptSectionBuilder.single(contribution));
      return;
    }

    final index = sections.indexWhere(
      (section) => section.id == contribution.id && section.role == role,
    );
    if (index < 0) {
      sections.add(_PromptSectionBuilder.single(contribution));
      return;
    }

    final existing = sections[index];
    final comparison = _compareLayers(existing.scope, contribution.scope);
    if (role == PromptMergeRole.replace && comparison == 0) {
      diagnostics.add(
        ResourceAssemblyDiagnostic(
          severity: ResourceAssemblyDiagnosticSeverity.warning,
          resourceKind: ResourceContributionKind.prompt,
          cli: cli,
          providerId: contribution.origin.providerId,
          sourceId: contribution.origin.sourceId,
          message:
              'Prompt replace conflict for id ${contribution.id}; '
              'later ${_originLabel(contribution.origin)} replaced earlier '
              '${_originLabel(existing.origin)}.',
        ),
      );
      sections[index] = _PromptSectionBuilder.single(contribution);
      return;
    }

    if (comparison > 0) {
      diagnostics.add(
        ResourceAssemblyDiagnostic(
          severity: ResourceAssemblyDiagnosticSeverity.warning,
          resourceKind: ResourceContributionKind.prompt,
          cli: cli,
          providerId: existing.origin.providerId,
          sourceId: existing.origin.sourceId,
          message:
              'Lower-layer prompt ${_originLabel(existing.origin)} was '
              'retained as appended content after higher-layer '
              '${_originLabel(contribution.origin)} took precedence.',
        ),
      );
      sections[index] = _PromptSectionBuilder.single(contribution);
      sections.insert(index + 1, existing.asAppend());
      return;
    }

    if (comparison < 0) {
      diagnostics.add(
        ResourceAssemblyDiagnostic(
          severity: ResourceAssemblyDiagnosticSeverity.warning,
          resourceKind: ResourceContributionKind.prompt,
          cli: cli,
          providerId: contribution.origin.providerId,
          sourceId: contribution.origin.sourceId,
          message:
              'Lower-layer prompt ${_originLabel(contribution.origin)} '
              'was retained as appended content; higher-layer '
              '${_originLabel(existing.origin)} remains authoritative.',
        ),
      );
      sections.add(
        _PromptSectionBuilder.single(
          contribution,
          role: PromptMergeRole.append,
        ),
      );
      return;
    }

    diagnostics.add(
      ResourceAssemblyDiagnostic(
        severity: ResourceAssemblyDiagnosticSeverity.warning,
        resourceKind: ResourceContributionKind.prompt,
        cli: cli,
        providerId: contribution.origin.providerId,
        sourceId: contribution.origin.sourceId,
        message:
            'Prompt section conflict for id ${contribution.id}; '
            'merged ${_originLabel(contribution.origin)} with earlier '
            '${_originLabel(existing.origin)}.',
      ),
    );
    existing.contributions.add(contribution);
  }

  String _originLabel(ContributionOrigin origin) =>
      '${origin.providerId}/${origin.sourceId ?? '<none>'}';

  int _compareLayers(PromptScope left, PromptScope right) {
    return _layer(right).compareTo(_layer(left));
  }

  int _layer(PromptScope scope) => switch (scope) {
    PromptScope.cli => 0,
    PromptScope.global => 1,
    PromptScope.workspace => 2,
    PromptScope.expert => 3,
    PromptScope.team => 4,
    PromptScope.member => 5,
  };
}

/// Result of prompt assembly plus the shared diagnostic projection.
final class PromptAssemblyResult {
  const PromptAssemblyResult({required this.document, required this.assembly});

  final PromptDocument document;
  final ResourceAssemblyResult assembly;

  List<ResourceAssemblyDiagnostic> get diagnostics => assembly.diagnostics;
  List<ResourceAssemblyDiagnostic> get warnings => assembly.warnings;
  List<ResourceAssemblyDiagnostic> get errors => assembly.errors;
}

final class _PromptSectionBuilder {
  _PromptSectionBuilder({required this.contributions, PromptMergeRole? role})
    : id = contributions.first.id,
      role = role ?? contributions.first.mergeRole,
      scope = contributions.first.scope,
      origin = contributions.first.origin;

  factory _PromptSectionBuilder.single(
    PromptContribution contribution, {
    PromptMergeRole? role,
  }) => _PromptSectionBuilder(contributions: [contribution], role: role);

  final String id;
  final PromptMergeRole role;
  final PromptScope scope;
  final ContributionOrigin origin;
  final List<PromptContribution> contributions;

  _PromptSectionBuilder asAppend() => _PromptSectionBuilder(
    contributions: contributions,
    role: PromptMergeRole.append,
  );

  PromptSection build() => PromptSection(
    id: id,
    title: contributions.first.title,
    scope: scope,
    contributions: contributions,
  );
}

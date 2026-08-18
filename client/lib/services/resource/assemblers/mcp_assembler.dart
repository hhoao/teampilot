import 'dart:async';

import '../../../models/mcp_server_spec.dart';
import '../../../models/team_config.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_assembly_result.dart';
import '../contribution/resource_origin.dart';
import '../providers/mcp_contribution_provider.dart';

/// Assembles target-neutral MCP servers in deterministic provider order.
final class McpAssembler {
  const McpAssembler();

  Future<McpAssemblyResult> assemble({
    required McpProviderContext context,
    required Iterable<McpContributionProvider> providers,
  }) async {
    final orderedProviders = List<McpContributionProvider>.of(providers);
    final provided = await Future.wait<_ProvidedMcp>([
      for (final provider in orderedProviders) _provide(provider, context),
    ]);

    final providerErrors = <ResourceAssemblyError>[];
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final orderedKeys = <String>[];
    final selected = <String, McpContribution>{};

    for (final batch in provided) {
      providerErrors.addAll(batch.errors);
      diagnostics.addAll(batch.diagnostics);
      for (final contribution in batch.contributions) {
        _validate(contribution, context.cli);
        final key = _serverKey(contribution.server);
        final previous = selected[key];
        if (previous == null) {
          selected[key] = contribution;
          orderedKeys.add(key);
          continue;
        }

        if (previous.server == contribution.server) continue;

        final layerComparison = _layer(
          contribution.origin.kind,
        ).compareTo(_layer(previous.origin.kind));
        if (layerComparison == 0) {
          throw ResourceAssemblyException([
            ResourceAssemblyError.conflict(
              resourceKind: ResourceContributionKind.mcp,
              cli: context.cli,
              providerId: contribution.origin.providerId,
              sourceId: contribution.sourceId,
              message:
                  'MCP server key $key has different payloads at the same '
                  'layer; retained ${_originLabel(previous.origin)} only '
                  'after rejecting ${_originLabel(contribution.origin)}.',
            ),
          ]);
        }

        final higher = layerComparison > 0 ? contribution : previous;
        final lower = layerComparison > 0 ? previous : contribution;
        if (higher == contribution) selected[key] = contribution;
        diagnostics.add(
          ResourceAssemblyDiagnostic(
            severity: ResourceAssemblyDiagnosticSeverity.warning,
            resourceKind: ResourceContributionKind.mcp,
            cli: context.cli,
            providerId: lower.origin.providerId,
            sourceId: lower.sourceId,
            message:
                'MCP server key $key from ${_originLabel(lower.origin)} was '
                'overridden by higher-layer ${_originLabel(higher.origin)}.',
          ),
        );
      }
    }

    if (providerErrors.isNotEmpty) {
      throw ResourceAssemblyException(providerErrors);
    }

    return McpAssemblyResult(
      servers: [for (final key in orderedKeys) selected[key]!.server],
      assembly: ResourceAssemblyResult(diagnostics: diagnostics),
    );
  }

  Future<_ProvidedMcp> _provide(
    McpContributionProvider provider,
    McpProviderContext context,
  ) async {
    try {
      final contributions = List<McpContribution>.unmodifiable(
        await provider.provide(context),
      );
      final diagnostics = provider is McpContributionProviderDiagnostics
          ? List<ResourceAssemblyDiagnostic>.unmodifiable(
              (provider as McpContributionProviderDiagnostics).diagnostics,
            )
          : const <ResourceAssemblyDiagnostic>[];
      return _ProvidedMcp(
        contributions: contributions,
        diagnostics: diagnostics,
        errors: const [],
      );
    } on ResourceAssemblyException catch (error) {
      return _ProvidedMcp(
        contributions: const [],
        diagnostics: const [],
        errors: error.diagnostics,
      );
    } on Object catch (error, stackTrace) {
      return _ProvidedMcp(
        contributions: const [],
        diagnostics: const [],
        errors: [
          ResourceAssemblyError.provider(
            resourceKind: ResourceContributionKind.mcp,
            cli: context.cli,
            providerId: provider.providerId,
            sourceId: context.sourceId ?? provider.providerId,
            message: 'MCP contribution provider failed: $error',
            cause: error,
            stackTrace: stackTrace,
          ),
        ],
      );
    }
  }

  void _validate(McpContribution contribution, CliTool cli) {
    if (contribution.sourceId.trim().isNotEmpty &&
        contribution.server.name.trim().isNotEmpty) {
      return;
    }
    throw ResourceAssemblyException([
      ResourceAssemblyError.provider(
        resourceKind: ResourceContributionKind.mcp,
        cli: cli,
        providerId: contribution.origin.providerId,
        sourceId: contribution.sourceId,
        message: 'MCP contribution source id and server name are required.',
      ),
    ]);
  }

  String _serverKey(McpServerSpec server) => server.name.trim();

  int _layer(ResourceOriginKind kind) => switch (kind) {
    ResourceOriginKind.cliBuiltIn => 0,
    ResourceOriginKind.catalog => 1,
    ResourceOriginKind.plugin => 2,
    ResourceOriginKind.extension => 2,
    ResourceOriginKind.workspace => 3,
    ResourceOriginKind.expert => 4,
    ResourceOriginKind.team => 5,
    ResourceOriginKind.managed => 6,
  };

  String _originLabel(ContributionOrigin origin) =>
      '${origin.providerId}/${origin.sourceId ?? '<none>'}';
}

final class _ProvidedMcp {
  const _ProvidedMcp({
    required this.contributions,
    required this.diagnostics,
    required this.errors,
  });

  final List<McpContribution> contributions;
  final List<ResourceAssemblyDiagnostic> diagnostics;
  final List<ResourceAssemblyError> errors;
}

/// Result of MCP assembly plus its immutable diagnostic projection.
final class McpAssemblyResult {
  McpAssemblyResult({
    required Iterable<McpServerSpec> servers,
    required this.assembly,
  }) : servers = List.unmodifiable(servers);

  final List<McpServerSpec> servers;
  final ResourceAssemblyResult assembly;

  List<ResourceAssemblyDiagnostic> get diagnostics => assembly.diagnostics;
  List<ResourceAssemblyDiagnostic> get warnings => assembly.warnings;
  List<ResourceAssemblyDiagnostic> get errors => assembly.errors;
}

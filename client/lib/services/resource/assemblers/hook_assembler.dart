import 'dart:async';

import '../../../models/hook_entry.dart';
import '../../../models/hook_event.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_assembly_result.dart';
import '../contribution/resource_origin.dart';
import '../providers/hook_contribution_provider.dart';

/// Assembles target-neutral hooks in deterministic provider order.
final class HookAssembler {
  const HookAssembler();

  Future<HookAssemblyResult> assemble({
    required HookProviderContext context,
    required Iterable<HookContributionProvider> providers,
  }) async {
    final orderedProviders = List<HookContributionProvider>.of(providers);
    if (orderedProviders.isEmpty) {
      return HookAssemblyResult(
        entries: const [],
        assembly: ResourceAssemblyResult(diagnostics: const []),
      );
    }

    final provided = await Future.wait<_ProvidedHooks>([
      for (final provider in orderedProviders) _provide(provider, context),
    ]);
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final errors = <ResourceAssemblyError>[];
    final selected = <String, _SelectedHook>{};
    final orderedKeys = <String>[];

    for (
      var providerIndex = 0;
      providerIndex < provided.length;
      providerIndex++
    ) {
      final batch = provided[providerIndex];
      diagnostics.addAll(batch.diagnostics);
      errors.addAll(batch.errors);
      final provider = orderedProviders[providerIndex];
      for (final contribution in batch.contributions) {
        final support = HookEventCapability.support(
          contribution.entry.event,
          context.cli,
        );
        if (!support.supported) {
          final diagnostic = ResourceAssemblyError.unsupported(
            resourceKind: ResourceContributionKind.hook,
            cli: context.cli,
            providerId: provider.providerId,
            sourceId: contribution.sourceId,
            message:
                'Hook event ${contribution.entry.event.name} is unsupported '
                'by ${context.cli.value}.',
          );
          if (_isOptional(provider, contribution)) {
            diagnostics.add(_asWarning(diagnostic));
          } else {
            errors.add(diagnostic);
          }
          continue;
        }
        if (contribution.entry.action is HttpHookAction &&
            !context.supportsHttp) {
          final diagnostic = ResourceAssemblyError.unsupported(
            resourceKind: ResourceContributionKind.hook,
            cli: context.cli,
            providerId: provider.providerId,
            sourceId: contribution.sourceId,
            message:
                'HTTP hook ${contribution.entry.id} is unsupported by '
                '${context.cli.value} (HookCapability.supportsHttp=false).',
          );
          if (_isOptional(provider, contribution)) {
            diagnostics.add(_asWarning(diagnostic));
          } else {
            errors.add(diagnostic);
          }
          continue;
        }

        final key = _identity(contribution.entry);
        final previous = selected[key];
        if (previous == null) {
          selected[key] = _SelectedHook(
            contribution,
            provider.providerId,
            optional: _isOptional(provider, contribution),
          );
          orderedKeys.add(key);
          continue;
        }
        if (_payload(previous.contribution.entry) ==
            _payload(contribution.entry)) {
          continue;
        }
        final currentOptional = _isOptional(provider, contribution);
        if (currentOptional || previous.optional) {
          if (currentOptional) {
            diagnostics.add(
              _asWarning(
                _conflict(
                  context: context,
                  key: key,
                  providerId: provider.providerId,
                  sourceId: contribution.sourceId,
                  previousProviderId: previous.providerId,
                  previousSourceId: previous.contribution.sourceId,
                  message:
                      'Optional hook ${_label(previous)} was skipped '
                      'because required hook ${provider.providerId}/'
                      '${contribution.sourceId} has the same identity.',
                ),
              ),
            );
          } else {
            diagnostics.add(
              _asWarning(
                _conflict(
                  context: context,
                  key: key,
                  providerId: previous.providerId,
                  sourceId: previous.contribution.sourceId,
                  previousProviderId: provider.providerId,
                  previousSourceId: contribution.sourceId,
                  message:
                      'Optional hook ${_label(previous)} was replaced '
                      'by required ${provider.providerId}/'
                      '${contribution.sourceId}.',
                ),
              ),
            );
            selected[key] = _SelectedHook(
              contribution,
              provider.providerId,
              optional: false,
            );
          }
          continue;
        }
        errors.add(
          _conflict(
            context: context,
            key: key,
            providerId: provider.providerId,
            sourceId: contribution.sourceId,
            previousProviderId: previous.providerId,
            previousSourceId: previous.contribution.sourceId,
          ),
        );
      }
    }

    if (errors.isNotEmpty) {
      throw ResourceAssemblyException(errors);
    }
    return HookAssemblyResult(
      entries: [
        for (final key in orderedKeys) selected[key]!.contribution.entry,
      ],
      assembly: ResourceAssemblyResult(diagnostics: diagnostics),
    );
  }

  Future<_ProvidedHooks> _provide(
    HookContributionProvider provider,
    HookProviderContext context,
  ) async {
    try {
      final contributions = List<HookContribution>.unmodifiable(
        await provider.provide(context),
      );
      final diagnostics = provider is HookContributionProviderDiagnostics
          ? List<ResourceAssemblyDiagnostic>.unmodifiable(
              (provider as HookContributionProviderDiagnostics).diagnostics,
            )
          : const <ResourceAssemblyDiagnostic>[];
      return _ProvidedHooks(
        contributions: contributions,
        diagnostics: diagnostics,
        errors: const [],
      );
    } on ResourceAssemblyException catch (error) {
      if (_isOptional(provider, null)) {
        return _ProvidedHooks(
          contributions: const [],
          diagnostics: [
            for (final diagnostic in error.diagnostics) _asWarning(diagnostic),
          ],
          errors: const [],
        );
      }
      return _ProvidedHooks(
        contributions: const [],
        diagnostics: const [],
        errors: error.diagnostics,
      );
    } on Object catch (error, stackTrace) {
      final diagnostic = ResourceAssemblyError.provider(
        resourceKind: ResourceContributionKind.hook,
        cli: context.cli,
        providerId: provider.providerId,
        sourceId: context.sourceId ?? provider.providerId,
        message: 'Hook contribution provider failed: $error',
        cause: error,
        stackTrace: stackTrace,
      );
      if (_isOptional(provider, null)) {
        return _ProvidedHooks(
          contributions: const [],
          diagnostics: [_asWarning(diagnostic)],
          errors: const [],
        );
      }
      return _ProvidedHooks(
        contributions: const [],
        diagnostics: const [],
        errors: [diagnostic],
      );
    }
  }

  bool _isOptional(
    HookContributionProvider provider,
    HookContribution? contribution,
  ) {
    if (provider is HookContributionProviderOptional &&
        (provider as HookContributionProviderOptional).optional) {
      return true;
    }
    final kind = contribution?.origin.kind;
    return kind == ResourceOriginKind.plugin ||
        kind == ResourceOriginKind.extension ||
        provider.providerId == 'plugin' ||
        provider.providerId == 'extension';
  }

  ResourceAssemblyDiagnostic _asWarning(
    ResourceAssemblyDiagnostic diagnostic,
  ) => ResourceAssemblyDiagnostic(
    severity: ResourceAssemblyDiagnosticSeverity.warning,
    resourceKind: diagnostic.resourceKind,
    cli: diagnostic.cli,
    providerId: diagnostic.providerId,
    sourceId: diagnostic.sourceId,
    previousProviderId: diagnostic.previousProviderId,
    previousSourceId: diagnostic.previousSourceId,
    message: diagnostic.message,
    cause: diagnostic.cause,
    stackTrace: diagnostic.stackTrace,
  );

  ResourceAssemblyError _conflict({
    required HookProviderContext context,
    required String key,
    required String providerId,
    required String sourceId,
    required String previousProviderId,
    required String previousSourceId,
    String? message,
  }) => ResourceAssemblyError.conflict(
    resourceKind: ResourceContributionKind.hook,
    cli: context.cli,
    providerId: providerId,
    sourceId: sourceId,
    previousProviderId: previousProviderId,
    previousSourceId: previousSourceId,
    message:
        message ??
        'Hook identity $key has different payloads between '
            '$previousProviderId/$previousSourceId and $providerId/$sourceId.',
  );

  String _identity(HookEntry entry) {
    final matcher = entry.matcher?.trim() ?? '';
    final action = switch (entry.action) {
      CommandHookAction c =>
        c.command != null
            ? 'command:${_normalize(c.command!)}'
            : 'script:${_normalize(c.fileName ?? '')}\u0000'
                  '${_normalize(c.scriptContent ?? '')}',
      HttpHookAction h => 'http:${_normalize(h.url)}\u0000${_map(h.headers)}',
    };
    return '${entry.event.name}\u0000$matcher\u0000${entry.policy.name}\u0000$action';
  }

  String _payload(HookEntry entry) {
    final env = _map(entry.env);
    return '${entry.timeout?.inMicroseconds ?? ''}\u0000$env\u0000'
        '${entry.blockOnDecision}';
  }

  String _normalize(String value) => value.trim();

  String _map(Map<String, String> value) {
    final entries = value.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join('\u0001');
  }

  String _label(_SelectedHook selected) =>
      '${selected.providerId}/${selected.contribution.sourceId}';
}

final class _ProvidedHooks {
  const _ProvidedHooks({
    required this.contributions,
    required this.diagnostics,
    required this.errors,
  });

  final List<HookContribution> contributions;
  final List<ResourceAssemblyDiagnostic> diagnostics;
  final List<ResourceAssemblyError> errors;
}

final class _SelectedHook {
  const _SelectedHook(
    this.contribution,
    this.providerId, {
    required this.optional,
  });

  final HookContribution contribution;
  final String providerId;
  final bool optional;
}

/// Assembled hooks plus their immutable diagnostic projection.
final class HookAssemblyResult {
  HookAssemblyResult({
    required Iterable<HookEntry> entries,
    required this.assembly,
  }) : entries = List.unmodifiable(entries);

  final List<HookEntry> entries;
  final ResourceAssemblyResult assembly;

  List<ResourceAssemblyDiagnostic> get diagnostics => assembly.diagnostics;
  List<ResourceAssemblyDiagnostic> get warnings => assembly.warnings;
  List<ResourceAssemblyDiagnostic> get errors => assembly.errors;
}

import '../../../models/hook_entry.dart';
import '../../hook/hook_library_resolver.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import 'hook_contribution_provider.dart';

/// Reads enabled user-library hook definitions into neutral contributions.
final class HookLibraryContributionProvider
    implements HookContributionProvider, HookContributionProviderDiagnostics {
  HookLibraryContributionProvider({
    required HookLibraryResolver resolver,
    required Iterable<String> hookIds,
    this.originKind = ResourceOriginKind.workspace,
  }) : _resolver = resolver,
       hookIds = List.unmodifiable(hookIds);

  final HookLibraryResolver _resolver;
  final List<String> hookIds;
  final ResourceOriginKind originKind;
  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  String get providerId => 'user-library';

  @override
  List<ResourceAssemblyDiagnostic> get diagnostics => _diagnostics;

  @override
  Future<Iterable<HookContribution>> provide(
    HookProviderContext context,
  ) async {
    final resolved = await _resolver.resolveForProvider(hookIds);
    _diagnostics = List.unmodifiable(
      resolved.warnings.map(
        (warning) => ResourceAssemblyDiagnostic(
          severity: ResourceAssemblyDiagnosticSeverity.warning,
          resourceKind: ResourceContributionKind.hook,
          cli: context.cli,
          providerId: providerId,
          sourceId: warning,
          message: warning,
        ),
      ),
    );
    return [
      for (final entry in resolved.entries)
        HookContribution(
          sourceId: entry.id,
          entry: entry,
          origin: ContributionOrigin(
            providerId: providerId,
            kind: originKind,
            sourceId: entry.id,
          ),
        ),
    ];
  }
}

/// Adapts entries already resolved from the user library (for example by a
/// launch staging facade) without resolving or materializing them again.
final class UserHookContributionProvider implements HookContributionProvider {
  UserHookContributionProvider({
    required Iterable<HookEntry> entries,
    this.originKind = ResourceOriginKind.workspace,
    this.providerId = 'user-library',
  }) : entries = List.unmodifiable(entries);

  final List<HookEntry> entries;
  final ResourceOriginKind originKind;

  @override
  final String providerId;

  @override
  Iterable<HookContribution> provide(HookProviderContext context) => [
    for (final entry in entries)
      HookContribution(
        sourceId: entry.id,
        entry: entry,
        origin: ContributionOrigin(
          providerId: providerId,
          kind: originKind,
          sourceId: entry.id,
        ),
      ),
  ];
}

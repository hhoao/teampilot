import '../../../models/hook_entry.dart';
import '../contribution/resource_origin.dart';
import 'hook_contribution_provider.dart';

/// Adapts already-created managed HookEntry values without materializing them.
final class ManagedHookContributionProvider
    implements HookContributionProvider {
  ManagedHookContributionProvider({
    required Iterable<HookEntry> entries,
    this.providerId = 'managed',
  }) : entries = List.unmodifiable(entries);

  final List<HookEntry> entries;

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
          kind: ResourceOriginKind.managed,
          sourceId: entry.id,
        ),
      ),
  ];
}

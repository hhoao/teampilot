import '../../../models/hook_entry.dart';
import '../../extension/extension_provisioner.dart';
import '../../cli/registry/config_profile/hook_seat_context_completer.dart';
import '../contribution/resource_origin.dart';
import 'hook_contribution_provider.dart';

/// Converts optional extension hook inputs to neutral contributions.
final class ExtensionHookContributionProvider
    implements HookContributionProvider, HookContributionProviderOptional {
  ExtensionHookContributionProvider({
    Iterable<HookEntry> entries = const [],
    Iterable<ExtensionSettingsHook> settingsHooks = const [],
    this.providerId = 'extension',
  }) : entries = List.unmodifiable([
         ...entries,
         for (final hook in settingsHooks)
           ...const HookSeatContextCompleter().extensionHooks(
             extensionId: hook.extensionId,
             events: [hook.event],
             command: hook.command,
             matcher: hook.matcher,
           ),
       ]);

  final List<HookEntry> entries;

  @override
  final String providerId;

  @override
  bool get optional => true;

  @override
  Iterable<HookContribution> provide(HookProviderContext context) => [
    for (final entry in entries)
      HookContribution(
        sourceId: entry.id,
        entry: entry,
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.extension,
          sourceId: entry.id,
        ),
      ),
  ];
}

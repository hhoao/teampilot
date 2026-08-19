import '../../../models/hook_entry.dart';
import '../../../models/plugin.dart';
import '../../cli/registry/config_profile/hook_seat_context_completer.dart';
import '../contribution/resource_origin.dart';
import 'hook_contribution_provider.dart';

/// Converts optional plugin hook metadata and supplied commands to neutral
/// contributions. It never reads or writes a CLI plugin directory.
final class PluginHookContributionProvider
    implements HookContributionProvider, HookContributionProviderOptional {
  PluginHookContributionProvider({
    Iterable<HookEntry> entries = const [],
    Iterable<PluginHook> hooks = const [],
    String command = '',
    this.providerId = 'plugin',
  }) : entries = List.unmodifiable([
         ...entries,
         ...const HookSeatContextCompleter().pluginHooks(
           hooks: hooks.toList(growable: false),
           command: command,
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
          kind: ResourceOriginKind.plugin,
          sourceId: entry.id,
        ),
      ),
  ];
}

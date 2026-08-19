import '../../../models/hook_event.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/config_profile/hook_seat_context_completer.dart';
import '../contribution/resource_origin.dart';
import 'hook_contribution_provider.dart';

/// Mixed TeamBus SessionStart awareness (Superpowers-style additionalContext).
///
/// OpenCode has no `sessionStart`; this provider contributes nothing there.
/// OpenCode injects the same protocol via `teampilot-bus-awareness.js`.
final class BusAwarenessHookContributionProvider
    implements HookContributionProvider {
  const BusAwarenessHookContributionProvider();

  @override
  String get providerId => 'bus-awareness';

  @override
  Iterable<HookContribution> provide(HookProviderContext context) {
    final member = context.member;
    if (member == null || !member.isValid) return const [];
    if (!HookEventCapability.supports(HookEvent.sessionStart, context.cli)) {
      return const [];
    }
    final entries = const HookSeatContextCompleter().busAwarenessHooks(
      member: member,
      cli: context.cli,
      pushDelivery: context.cli == CliTool.cursor,
    );
    return [
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
}

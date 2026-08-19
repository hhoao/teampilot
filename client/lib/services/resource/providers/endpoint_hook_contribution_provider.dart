import '../../../models/hook_entry.dart';
import '../../../models/hook_event.dart';
import '../../agent_status/member_agent_status_endpoint.dart';
import '../../cli/registry/config_profile/hook_seat_context_completer.dart';
import '../../team_bus/member_bus_idle_endpoint.dart';
import '../contribution/resource_origin.dart';
import 'hook_contribution_provider.dart';

/// Generic managed endpoint-backed hook provider for already-built entries.
///
/// HTTP endpoint hooks (agent-status / bus-idle) are skipped when the CLI
/// [HookProviderContext.supportsHttp] is false. Those CLIs keep a native
/// plugin path instead of failing closed in the shared assembler.
class EndpointHookContributionProvider implements HookContributionProvider {
  EndpointHookContributionProvider({
    required Iterable<HookEntry> entries,
    this.providerId = 'endpoint',
  }) : entries = List.unmodifiable(entries);

  final List<HookEntry> entries;

  @override
  final String providerId;

  @override
  Iterable<HookContribution> provide(HookProviderContext context) => [
    for (final entry in entries)
      if (_isSupported(entry, context))
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

  bool _isSupported(HookEntry entry, HookProviderContext context) {
    if (!HookEventCapability.supports(entry.event, context.cli)) {
      return false;
    }
    return entry.action is! HttpHookAction || context.supportsHttp;
  }
}

/// Agent-status endpoint provider; hook construction stays in the completer.
final class AgentStatusHookContributionProvider
    extends EndpointHookContributionProvider {
  AgentStatusHookContributionProvider({
    required MemberAgentStatusEndpoint endpoint,
    required String memberId,
  }) : super(
         providerId: 'agent-status',
         entries: const HookSeatContextCompleter().agentStatusHooks(
           endpoint: endpoint,
           memberId: memberId,
         ),
       );
}

/// TeamBus idle endpoint provider; hook construction stays in the completer.
final class BusIdleHookContributionProvider
    extends EndpointHookContributionProvider {
  BusIdleHookContributionProvider({
    required MemberBusIdleEndpoint endpoint,
    required String memberId,
  }) : super(
         providerId: 'bus-idle',
         entries: const HookSeatContextCompleter().busIdleHooks(
           idle: endpoint,
           memberId: memberId,
         ),
       );
}

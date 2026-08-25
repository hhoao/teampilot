import '../../agent_status/member_agent_status_endpoint.dart';
import '../../cli/registry/capabilities/runtime_event_capability.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../../models/hook_entry.dart';
import '../../../models/hook_event.dart';
import '../contribution/resource_origin.dart';
import 'hook_contribution_provider.dart';

/// Contributes capability-owned runtime HookEntry values to the shared hook
/// assembly. It never writes CLI config or scripts itself.
final class RuntimeEventHookContributionProvider
    implements HookContributionProvider {
  RuntimeEventHookContributionProvider({
    required this.endpoint,
    required this.memberId,
    CliToolRegistry? registry,
  }) : _registry = registry ?? CliToolRegistry.builtIn();

  final MemberAgentStatusEndpoint endpoint;
  final String memberId;
  final CliToolRegistry _registry;

  @override
  String get providerId => 'runtime-event';

  @override
  Iterable<HookContribution> provide(HookProviderContext context) {
    final capability = _registry.capability<RuntimeEventCapability>(
      context.cli,
    );
    if (capability == null) return const [];
    final entries = capability.managedHookEntries(
      RuntimeEventHookContext(endpoint: endpoint, memberId: memberId),
    );
    return [
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
  }

  /// Returns a target-native runtime plugin when the selected capability needs
  /// one instead of a native HTTP hook writer (currently OpenCode).
  RuntimeEventNativePluginContribution? nativePluginContribution(
    HookProviderContext context,
  ) {
    final capability = _registry.capability<RuntimeEventNativePluginCapability>(
      context.cli,
    );
    return capability?.managedPluginContribution(
      RuntimeEventHookContext(endpoint: endpoint, memberId: memberId),
    );
  }

  bool _isSupported(HookEntry entry, HookProviderContext context) =>
      HookEventCapability.supports(entry.event, context.cli) &&
      (entry.action is! HttpHookAction || context.supportsHttp);
}

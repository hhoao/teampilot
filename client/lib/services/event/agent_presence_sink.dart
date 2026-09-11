import 'agent_presence_event.dart';
import 'dispatcher.dart';

/// Narrow publish seam for presence events.
///
/// Domain layers (services/team, services/terminal) depend on THIS, never on
/// the dispatcher itself — keeps the heuristic/state-machine layers free of
/// event-layer imports.
abstract interface class AgentPresenceSink {
  void publish(AgentPresenceEvent event);
}

/// Publishes onto the central dispatcher.
final class DispatcherAgentPresenceSink implements AgentPresenceSink {
  const DispatcherAgentPresenceSink(this._dispatcher);

  final Dispatcher _dispatcher;

  @override
  void publish(AgentPresenceEvent event) => _dispatcher.dispatch(event);
}

/// Used when no dispatcher is wired (tests, early startup).
final class NoopAgentPresenceSink implements AgentPresenceSink {
  const NoopAgentPresenceSink();

  @override
  void publish(AgentPresenceEvent event) {}
}

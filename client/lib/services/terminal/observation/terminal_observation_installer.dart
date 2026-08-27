import '../../cli/registry/capabilities/terminal_observation_contributor.dart';
import '../../cli/registry/cli_capability.dart';
import 'terminal_observation_bus.dart';
import 'terminal_observation_seat.dart';

final class TerminalObservationConnectRequest {
  const TerminalObservationConnectRequest({
    required this.isWorkspaceShell,
    this.cliCapabilities = const [],
    this.sessionModules = const [],
  });

  final bool isWorkspaceShell;
  final Iterable<CliCapability> cliCapabilities;
  final List<TerminalObservationContributor> sessionModules;
}

/// Binds session modules then CLI observation contributors onto a seat bus.
final class TerminalObservationInstaller {
  TerminalObservationBinding bind({
    required TerminalObservationBus bus,
    required TerminalObservationSeat seat,
    required TerminalObservationConnectRequest request,
  }) {
    final bindings = <TerminalObservationBinding>[
      for (final module in request.sessionModules) module.bind(bus, seat),
    ];
    if (!request.isWorkspaceShell) {
      for (final contributor
          in request.cliCapabilities
              .whereType<TerminalObservationContributor>()) {
        bindings.add(contributor.bind(bus, seat));
      }
    }
    return CompositeObservationBinding(bindings);
  }
}

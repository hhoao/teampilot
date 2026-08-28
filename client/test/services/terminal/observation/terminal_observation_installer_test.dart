import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_observation_contributor.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_events.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_installer.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_phase.dart';

void main() {
  late TerminalObservationSeat seat;
  late TerminalObservationBus bus;

  setUp(() {
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.running,
    );
    bus = TerminalObservationBus(seat: seat);
  });

  tearDown(() => bus.dispose());

  test('binds session modules then CLI contributors in definition order', () {
    final order = <String>[];
    final session = [
      _NamedContributor('s1', order),
      _NamedContributor('s2', order),
    ];
    final cliCaps = [
      _NamedContributor('c1', order),
      _NamedContributor('c2', order),
    ];
    final binding = TerminalObservationInstaller().bind(
      bus: bus,
      seat: seat,
      request: TerminalObservationConnectRequest(
        isWorkspaceShell: false,
        cliCapabilities: cliCaps,
        sessionModules: session,
      ),
    );
    expect(order, ['s1', 's2', 'c1', 'c2']);
    binding.unbind();
    order.clear();
    bus.dispatchOutput(Uint8List.fromList([1]));
    expect(order, isEmpty);
  });

  test('workspace shell does not bind CLI contributors', () {
    final order = <String>[];
    TerminalObservationInstaller().bind(
      bus: bus,
      seat: seat,
      request: TerminalObservationConnectRequest(
        isWorkspaceShell: true,
        cliCapabilities: [_NamedContributor('cursor', order)],
        sessionModules: [_NamedContributor('session', order)],
      ),
    );
    expect(order, ['session']);
  });

  test('skips CLI capabilities that are not observation contributors', () {
    final order = <String>[];
    TerminalObservationInstaller().bind(
      bus: bus,
      seat: seat,
      request: TerminalObservationConnectRequest(
        isWorkspaceShell: false,
        cliCapabilities: [_PlainCapability(), _NamedContributor('c1', order)],
        sessionModules: [_NamedContributor('s1', order)],
      ),
    );
    expect(order, ['s1', 'c1']);
  });
}

final class _NamedContributor
    implements CliCapability, TerminalObservationContributor {
  _NamedContributor(this.name, this.order);

  final String name;
  final List<String> order;

  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    order.add(name);
    final subscription = bus.addOutputObserver(
      _NamedOutputObserver(name, order),
      phases: {TerminalLaunchPhase.running},
    );
    return CallbackObservationBinding(subscription.cancel);
  }
}

final class _NamedOutputObserver implements TerminalOutputObserver {
  _NamedOutputObserver(this.name, this.order);

  final String name;
  final List<String> order;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    order.add(name);
  }
}

final class _PlainCapability implements CliCapability {}

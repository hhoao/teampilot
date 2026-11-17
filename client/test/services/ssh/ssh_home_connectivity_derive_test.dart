import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote/remote_connection_monitor.dart';
import 'package:teampilot/services/ssh/ssh_connection_gate.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_derive.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';

void main() {
  SshHomeConnectivityState derive({
    SshPhase phase = SshPhase.unreachable,
    bool storageLive = false,
    RemoteConnectionStatus monitor = RemoteConnectionStatus.connected,
    SshConnectionGateState gate = SshConnectionGateState.up,
    bool planeRebinding = false,
  }) => deriveSshHomeConnectivityState(
    previous: SshHomeConnectivityState(profileId: 'p', phase: phase),
    storageLive: storageLive,
    monitorStatus: monitor,
    gateState: gate,
    planeRebinding: planeRebinding,
  );

  test('a retired lease with a healthy gate and link is degraded, not down', () {
    final state = derive();
    expect(state.phase, SshPhase.degraded);
    expect(state.storageLive, isFalse);
    expect(state.isDown, isFalse);
  });

  test('a live lease beats every other signal', () {
    final state = derive(
      phase: SshPhase.failed,
      storageLive: true,
      monitor: RemoteConnectionStatus.reconnecting,
      gate: SshConnectionGateState.down,
    );
    expect(state.phase, SshPhase.up);
    expect(state.storageLive, isTrue);
  });

  test('an in-flight dial stays connecting', () {
    expect(derive(phase: SshPhase.connecting).phase, SshPhase.connecting);
  });

  test('a reconnecting monitor wins over a healthy gate', () {
    expect(
      derive(monitor: RemoteConnectionStatus.reconnecting).phase,
      SshPhase.reconnecting,
    );
  });

  test('a sticky failure is preserved', () {
    expect(derive(phase: SshPhase.failed).phase, SshPhase.failed);
  });

  test('a suspended gate stays suspended', () {
    expect(
      derive(gate: SshConnectionGateState.suspended).phase,
      SshPhase.suspended,
    );
  });

  test('a closed gate is unreachable even with a healthy monitor', () {
    expect(
      derive(gate: SshConnectionGateState.down).phase,
      SshPhase.unreachable,
    );
  });
}

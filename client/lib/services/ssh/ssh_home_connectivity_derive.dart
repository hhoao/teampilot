import '../remote/remote_connection_monitor.dart';
import 'ssh_connection_gate.dart';
import 'ssh_home_connectivity_state.dart';

/// Pure phase table for one SSH home. Extracted so each priority rule is
/// testable without a factory, worker or coordinator.
SshHomeConnectivityState deriveSshHomeConnectivityState({
  required SshHomeConnectivityState previous,
  required bool storageLive,
  required RemoteConnectionStatus monitorStatus,
  required SshConnectionGateState gateState,
  bool planeRebinding = false,
}) {
  final id = previous.profileId;
  if (storageLive) {
    return SshHomeConnectivityState.up(
      id,
    ).copyWith(planeRebinding: planeRebinding);
  }
  if (previous.phase == SshPhase.connecting) {
    return previous.copyWith(storageLive: false);
  }
  if (monitorStatus == RemoteConnectionStatus.reconnecting) {
    return previous.copyWith(phase: SshPhase.reconnecting, storageLive: false);
  }
  if (previous.phase == SshPhase.failed) {
    return previous.copyWith(storageLive: false);
  }
  if (gateState == SshConnectionGateState.suspended) {
    return previous.copyWith(phase: SshPhase.suspended, storageLive: false);
  }
  // Gate open + link healthy: only the storage lease retired (command timeout,
  // probe failure). Keep the shell; the next storage read reopens the lease.
  // Deliberately excludes `idle`: a boot that never opened the gate must still
  // surface `unreachable`, not silently claim a healthy degraded home.
  if (gateState == SshConnectionGateState.up &&
      (monitorStatus == RemoteConnectionStatus.connected ||
          monitorStatus == RemoteConnectionStatus.degraded)) {
    return previous.copyWith(
      phase: SshPhase.degraded,
      storageLive: false,
      clearFailure: true,
      clearErrorDetail: true,
    );
  }
  return previous.copyWith(phase: SshPhase.unreachable, storageLive: false);
}

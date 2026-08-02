import 'ssh_transport_close.dart';

/// Whether a transport close should move durable SSH work-home state.
class SshTransportCloseDecision {
  const SshTransportCloseDecision({
    required this.affectsDurableHome,
    required this.emitDisconnectNotification,
    required this.scheduleStorageReconnect,
  });

  /// Mark profile monitor down and enter the disconnect coalesce wave.
  final bool affectsDurableHome;

  /// Fire coordinator `onDisconnect` when the coalesce timer flushes.
  final bool emitDisconnectNotification;

  /// After flush, schedule storage-pool auto-reconnect (subject to latch).
  final bool scheduleStorageReconnect;

  static const ignore = SshTransportCloseDecision(
    affectsDurableHome: false,
    emitDisconnectNotification: false,
    scheduleStorageReconnect: false,
  );

  static const durableReconnect = SshTransportCloseDecision(
    affectsDurableHome: true,
    emitDisconnectNotification: true,
    scheduleStorageReconnect: true,
  );

  static const durableNoAutoReconnect = SshTransportCloseDecision(
    affectsDurableHome: true,
    emitDisconnectNotification: true,
    scheduleStorageReconnect: false,
  );
}

/// Pure policy: member intentional closes must not tear down work-home UX.
abstract final class SshTransportClosePolicy {
  SshTransportClosePolicy._();

  static SshTransportCloseDecision evaluate(SshTransportClosed closed) {
    if (closed.plane == SshTransportPlane.member) {
      if (isExpectedLocalSshTransportClose(closed)) {
        return SshTransportCloseDecision.ignore;
      }
      return SshTransportCloseDecision.durableReconnect;
    }

    // Storage plane.
    if (isExpectedLocalSshTransportClose(closed)) {
      return SshTransportCloseDecision.durableNoAutoReconnect;
    }
    return SshTransportCloseDecision.durableReconnect;
  }

  /// Non-[SshTransportClosed] errors are treated as unexpected durable faults
  /// (keepalive / legacy callers) so reconnect behavior stays conservative.
  static SshTransportCloseDecision evaluateError(Object error) {
    if (error is SshTransportClosed) return evaluate(error);
    return SshTransportCloseDecision.durableReconnect;
  }
}

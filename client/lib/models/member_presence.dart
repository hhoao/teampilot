/// Connection layer for a team member's terminal / agent.
enum MemberConnection { offline, connecting, connected }

/// Workload layer when [MemberConnection.connected].
enum MemberWorkload { idle, working }

/// Aggregated presence for the members panel.
class MemberPresence {
  const MemberPresence({
    required this.connection,
    this.workload,
  });

  const MemberPresence.offline()
    : connection = MemberConnection.offline,
      workload = null;

  final MemberConnection connection;
  final MemberWorkload? workload;

  bool get isOffline => connection == MemberConnection.offline;
  bool get isConnecting => connection == MemberConnection.connecting;
  bool get isConnected => connection == MemberConnection.connected;
  bool get isWorking =>
      connection == MemberConnection.connected &&
      workload == MemberWorkload.working;
  bool get isIdle =>
      connection == MemberConnection.connected &&
      workload == MemberWorkload.idle;

  @override
  bool operator ==(Object other) {
    return other is MemberPresence &&
        other.connection == connection &&
        other.workload == workload;
  }

  @override
  int get hashCode => Object.hash(connection, workload);
}

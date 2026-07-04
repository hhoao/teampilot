/// PTY transport layer for a team member's terminal.
enum MemberConnection { offline, connecting, connected }

/// Agent availability once [MemberConnection.connected].
///
/// Distinct phases:
/// - [booting]: PTY linked but TUI frame not stable, or (mixed + forceWait) not
///   yet parked in `wait_for_message`.
/// - [working]: in-turn / active PTY during a turn.
/// - [idle]: truly available (parked in wait, or push-CLI at quiet prompt).
enum MemberAvailability { booting, working, idle }

/// Aggregated presence for the members panel.
class MemberPresence {
  const MemberPresence({
    required this.connection,
    this.availability,
  });

  const MemberPresence.offline()
    : connection = MemberConnection.offline,
      availability = null;

  final MemberConnection connection;
  final MemberAvailability? availability;

  bool get isOffline => connection == MemberConnection.offline;
  bool get isConnecting => connection == MemberConnection.connecting;
  bool get isConnected => connection == MemberConnection.connected;
  bool get isBooting =>
      connection == MemberConnection.connected &&
      availability == MemberAvailability.booting;
  bool get isWorking =>
      connection == MemberConnection.connected &&
      availability == MemberAvailability.working;
  bool get isIdle =>
      connection == MemberConnection.connected &&
      availability == MemberAvailability.idle;

  @override
  bool operator ==(Object other) {
    return other is MemberPresence &&
        other.connection == connection &&
        other.availability == availability;
  }

  @override
  int get hashCode => Object.hash(connection, availability);
}

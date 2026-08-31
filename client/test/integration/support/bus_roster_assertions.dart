import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/teammate_snapshot.dart';

/// Reads live bus roster state for integration tests (no MCP round-trip).
TeammateSnapshot? memberSnapshot(TeamBus? bus, String memberId) {
  if (bus == null) return null;
  for (final m in bus.rosterSnapshot().members) {
    if (m.memberId == memberId) return m;
  }
  return null;
}

String formatRosterLine(TeammateSnapshot m) {
  return '${m.memberId}: lifecycle=${m.lifecycle.name} '
      'activity=${m.activity.name} phase=${m.busPhaseLabel} '
      'waiting=${m.waitingForMessage} pty=${m.ptyRunning} '
      'claudeActive=${m.claudeIsActive} unread=${m.unreadCount}';
}

String formatRosterSnapshot(TeamBus? bus) {
  if (bus == null) return '(no TeamBus)';
  final lines = bus.rosterSnapshot().members.map(formatRosterLine);
  return lines.join('\n');
}

/// Waits until [memberId] has an open SSE `wait_for_message` stream or
/// [MemberActivity.turnDoneBusWait] on the in-memory roster.
Future<void> waitUntilWorkerParked({
  required TeamBus? bus,
  required TeammateBusMcpGateway? gateway,
  required String sessionId,
  required String memberId,
  Duration timeout = const Duration(seconds: 90),
  Duration stableFor = const Duration(milliseconds: 250),
  bool allowSessionWaitStreams = true,
}) async {
  final deadline = DateTime.now().add(timeout);
  DateTime? parkedSince;
  while (DateTime.now().isBefore(deadline)) {
    final snap = memberSnapshot(bus, memberId);
    final streamOpen = allowSessionWaitStreams &&
        (gateway?.activeWaitStreamCountFor(sessionId) ?? 0) > 0;
    final busWait = snap?.waitingForMessage ?? false;
    final parked =
        busWait ||
        snap?.activity.name == 'turnDoneBusWait' ||
        streamOpen;
    if (parked) {
      parkedSince ??= DateTime.now();
      if (DateTime.now().difference(parkedSince) >= stableFor) return;
    } else {
      parkedSince = null;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'Timed out waiting for $memberId to park '
    '(streams=${gateway?.activeWaitStreamCountFor(sessionId) ?? 0}, '
    'roster:\n${formatRosterSnapshot(bus)})',
  );
}

Future<void> dumpBusRosterDiagnostics({
  required TeamBus? bus,
  required TeammateBusMcpGateway? gateway,
  required String sessionId,
}) async {
  // ignore: avoid_print
  print('--- bus roster (memory)');
  // ignore: avoid_print
  print(formatRosterSnapshot(bus));
  // ignore: avoid_print
  print(
    '--- mcp active wait streams: '
    '${gateway?.activeWaitStreamCountFor(sessionId) ?? 0}',
  );
}

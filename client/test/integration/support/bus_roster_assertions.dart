import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_server.dart';
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
  required TeammateBusMcpServer? mcpServer,
  required String memberId,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final snap = memberSnapshot(bus, memberId);
    final streamOpen = (mcpServer?.activeWaitStreamCount ?? 0) > 0;
    final busWait = snap?.waitingForMessage ?? false;
    if (streamOpen || busWait) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'Timed out waiting for $memberId to park '
    '(streams=${mcpServer?.activeWaitStreamCount ?? 0}, '
    'roster:\n${formatRosterSnapshot(bus)})',
  );
}

Future<void> dumpBusRosterDiagnostics({
  required TeamBus? bus,
  required TeammateBusMcpServer? mcpServer,
}) async {
  // ignore: avoid_print
  print('--- bus roster (memory)');
  // ignore: avoid_print
  print(formatRosterSnapshot(bus));
  // ignore: avoid_print
  print(
    '--- mcp active wait streams: ${mcpServer?.activeWaitStreamCount ?? 0}',
  );
}

@Tags(['integration', 'cross-platform'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/seat_lease_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/session_history_live_chrome.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_projection.dart';
import 'package:teampilot/services/agent_runtime/seat_lease_projection.dart';

/// End-to-end guard for the out-of-turn background-work axis, from the wire
/// payload all the way to the History tip footer.
///
/// Every other test stops at one hop: the normalizer, the projection, the
/// cubit, the resolver. This one chains them — a CLI's raw payload goes
/// through the real `seatLeaseProjection` (which normalizes via the registry)
/// into a real [SeatLeaseCubit], and the resulting state is fed to the real
/// [SessionHistoryLiveChromeX.resolve] the message area calls. It is the
/// closest thing to "observed in a running session" that does not need a live
/// PTY: it fails if any hop stops talking to the next.
void main() {
  const sessionId = 's1';
  const memberId = 'm1';

  RuntimeEventEnvelope envelope(
    CliTool cli,
    Map<String, Object?> raw,
    int sequence,
  ) => RuntimeEventEnvelope(
    seat: const RuntimeSeatKey(sessionId: sessionId, memberId: memberId),
    cli: cli,
    kind: RuntimeEventKind.statusReported,
    occurredAt: DateTime.utc(2026, 10, 15),
    sequence: sequence,
    raw: raw,
  );

  /// Exactly what `session_chat_message_area` passes: no turn in flight, the
  /// seat is up, and leases are read off the session.
  SessionHistoryLiveChrome chromeFor(SeatLeaseCubit leases) =>
      SessionHistoryLiveChromeX.resolve(
        turnInFlight: false,
        memberRunning: true,
        sessionConnecting: false,
        sessionHasLeases: leases.state.sessionHasLeases(sessionId),
      );

  late SeatLeaseCubit leases;
  late RuntimeEventProjection projection;

  setUp(() {
    leases = SeatLeaseCubit(pruneInterval: null);
    projection = seatLeaseProjection(leases: leases);
  });

  tearDown(() => leases.close());

  group('claude: Stop background_tasks snapshot drives the footer', () {
    test('a turn with no background work ends with no footer', () {
      projection.apply(
        envelope(CliTool.claude, {
          'hook_event_name': 'Stop',
          'background_tasks': <Object?>[],
        }, 1),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.none);
    });

    test('a paused background shell keeps the footer after the turn', () {
      projection.apply(
        envelope(CliTool.claude, {
          'hook_event_name': 'Stop',
          'background_tasks': [
            {'id': 't1', 'type': 'shell', 'status': 'running'},
          ],
        }, 1),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.background);
    });

    test('an older payload without the key leaves the footer alone', () {
      // flashskyai / older claude: absent must not read as "nothing running".
      projection.apply(
        envelope(CliTool.claude, {'hook_event_name': 'Stop'}, 1),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.none);
    });

    test('the next turn clearing the snapshot drops the footer', () {
      projection.apply(
        envelope(CliTool.claude, {
          'hook_event_name': 'Stop',
          'background_tasks': [
            {'id': 't1', 'type': 'subagent', 'status': 'running'},
          ],
        }, 1),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.background);

      projection.apply(
        envelope(CliTool.claude, {
          'hook_event_name': 'Stop',
          'background_tasks': <Object?>[],
        }, 2),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.none);
    });

    test('a <task-id>-only notification releases the snapshot lease', () {
      projection.apply(
        envelope(CliTool.claude, {
          'hook_event_name': 'Stop',
          'background_tasks': [
            {'id': 'bi6wlgsf3', 'type': 'shell', 'status': 'running'},
          ],
        }, 1),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.background);

      projection.apply(
        envelope(CliTool.claude, {
          'hook_event_name': 'UserPromptSubmit',
          'prompt':
              '<task-notification>\n'
              '<task-id>bi6wlgsf3</task-id>\n'
              '<status>completed</status>\n'
              '</task-notification>',
        }, 2),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.none);
    });
  });

  group('opencode: plugin events drive the footer', () {
    test('a background shell acquires then releases the footer', () {
      projection.apply(
        envelope(CliTool.opencode, {
          'event': 'shell.started',
          'shell_id': 'sh_1',
        }, 1),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.background);

      projection.apply(
        envelope(CliTool.opencode, {
          'event': 'shell.ended',
          'shell_id': 'sh_1',
        }, 2),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.none);
    });

    test('a child session (subagent) holds the footer until it stops', () {
      projection.apply(
        envelope(CliTool.opencode, {
          'event': 'subagent.started',
          'subagent_id': 'ses_child',
        }, 1),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.background);

      projection.apply(
        envelope(CliTool.opencode, {
          'event': 'subagent.stopped',
          'subagent_id': 'ses_child',
        }, 2),
      );
      expect(chromeFor(leases), SessionHistoryLiveChrome.none);
    });
  });
}

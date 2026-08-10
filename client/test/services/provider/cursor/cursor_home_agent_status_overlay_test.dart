import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_agent_status_overlay.dart';

void main() {
  const endpoint = MemberAgentStatusEndpoint(
    url: 'http://127.0.0.1:12345/agent-status',
    sessionId: 'session-1',
  );

  group('CursorHomeAgentStatusOverlay', () {
    test('scriptFor posts stdin payload to per-event URL with headers', () {
      final script = CursorHomeAgentStatusOverlay.scriptFor(
        endpoint: endpoint,
        memberId: 'm1',
        event: 'preToolUse',
      );
      expect(script, contains('/agent-status?event=preToolUse'));
      expect(script, contains('payload="\$(cat)"'));
      expect(script, contains('if [ -z "\$payload" ]'));
      expect(script, contains('-d "\$payload"'));
      expect(script, contains("-H 'X-Member: m1'"));
      expect(script, contains("-H 'X-Session: session-1'"));
      expect(script, contains('exit 0'));
    });

    test('mergeHooksConfig preserves existing stop and adds agent-status', () {
      final merged = CursorHomeAgentStatusOverlay.mergeHooksConfig(
        const {
          'version': 1,
          'hooks': {
            'stop': [
              {'command': "bash '/x/idle.sh'", 'loop_limit': null},
            ],
          },
        },
        scriptPathFor: (event) => '/home/.cursor/hooks/teampilot-agent-status-$event.sh',
      );
      final hooks = merged['hooks'] as Map;
      // Bus stop hook + agent-status stop hook both preserved.
      expect((hooks['stop'] as List), hasLength(2));
      for (final event in CursorHomeAgentStatusOverlay.statusEvents) {
        expect(hooks[event], isA<List>(), reason: event);
        final entries = hooks[event] as List;
        // stop carries the pre-existing bus hook too; others just the agent one.
        expect(entries, hasLength(event == 'stop' ? 2 : 1), reason: event);
        expect(
          entries.any(
            (e) =>
                e is Map &&
                e['command'] ==
                    "bash '/home/.cursor/hooks/teampilot-agent-status-$event.sh'",
          ),
          isTrue,
          reason: event,
        );
      }
    });

    test('mergeHooksConfig is idempotent', () {
      Map<String, Object?> merge() => CursorHomeAgentStatusOverlay.mergeHooksConfig(
        const <String, Object?>{},
        scriptPathFor: (_) => '/x.sh',
      );
      final once = merge();
      final twice = CursorHomeAgentStatusOverlay.mergeHooksConfig(
        once,
        scriptPathFor: (_) => '/x.sh',
      );
      expect(twice['hooks'], once['hooks']);
    });
  });
}

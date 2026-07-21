import '../core/turns.dart';
import 'mixed_collab_3plus.dart' show leadScriptApiKey, workerScriptApiKey;

export 'mixed_collab_3plus.dart' show leadScriptApiKey, workerScriptApiKey;

/// Logical `teambus.*` toolRefs (NOT raw `mcp__…` wire names). Wire mapping is
/// applied later via [CliTestProfile.toolName] / [ToolNameResolver].
Map<String, MockScenario> pingPongMixedClaudeScenarios() => {
      leadScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_list',
            toolRef: 'teambus.list_teammates',
            input: {},
          ),
          ToolUseTurn(
            id: 'tu_send',
            toolRef: 'teambus.send_message',
            input: {'to': 'worker-1', 'content': 'ping'},
          ),
          TextTurn('done'),
        ],
      ),
      workerScriptApiKey: MockScenario(
        turns: [
          // First wait: kickoff "Start idle loop." may return immediately when the
          // bus is empty; do not script pong on that turn.
          ToolUseTurn(
            id: 'tu_wait',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          // Second wait: blocks until the leader's ping arrives (docker is slower).
          ToolUseTurn(
            id: 'tu_wait_ping',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          ToolUseTurn(
            id: 'tu_reply',
            toolRef: 'teambus.send_message',
            input: {'to': 'team-lead', 'content': 'pong'},
          ),
          const TextTurn('done'),
        ],
      ),
    };

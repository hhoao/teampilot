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
          // Single wait: kickoff parks here until the lead's ping arrives.
          // A prior empty+second-wait pattern races when ping lands on the
          // first wait — worker then blocks until MCP cancel (~120s) before
          // pong, blowing the harness budget.
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

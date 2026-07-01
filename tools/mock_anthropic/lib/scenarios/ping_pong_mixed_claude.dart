import '../scenario.dart';

const leadScriptApiKey = 'lead-script';
const workerScriptApiKey = 'worker-script';

/// Claude Code registers teammate-bus MCP tools as `mcp__<server>__<tool>`.
const _bus = 'mcp__teammate-bus__';

ScenarioRegistry pingPongMixedClaudeScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_list', name: '${_bus}list_teammates', input: {}),
      ToolUseTurn(
        id: 'tu_send',
        name: '${_bus}send_message',
        input: {'to': 'worker-1', 'content': 'ping'},
      ),
      TextTurn('done'),
    ],
  ),
  workerScriptApiKey: MockScenario(
    turns: [
      // First wait: kickoff "Start idle loop." may return immediately when the
      // bus is empty; do not script pong on that turn.
      ToolUseTurn(id: 'tu_wait', name: '${_bus}wait_for_message', input: {}),
      // Second wait: blocks until the leader's ping arrives (docker is slower).
      ToolUseTurn(
        id: 'tu_wait_ping',
        name: '${_bus}wait_for_message',
        input: {},
      ),
      ToolUseTurn(
        id: 'tu_reply',
        name: '${_bus}send_message',
        input: {'to': 'team-lead', 'content': 'pong'},
      ),
      const TextTurn('done'),
    ],
  ),
});

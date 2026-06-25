import '../scenario.dart';

const leadScriptApiKey = 'lead-script';
const workerScriptApiKey = 'worker-script';

ScenarioRegistry pingPongMixedClaudeScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(turns: [
    ToolUseTurn(id: 'tu_list', name: 'list_teammates', input: {}),
    ToolUseTurn(
      id: 'tu_send',
      name: 'send_message',
      input: {'to': 'worker-1', 'content': 'ping'},
    ),
    TextTurn('done'),
  ]),
  workerScriptApiKey: MockScenario(turns: [
    ToolUseTurn(id: 'tu_wait', name: 'wait_for_message', input: {}),
    ToolUseTurn(
      id: 'tu_reply',
      name: 'send_message',
      input: {'to': 'team-lead', 'content': 'pong'},
    ),
  ]),
});

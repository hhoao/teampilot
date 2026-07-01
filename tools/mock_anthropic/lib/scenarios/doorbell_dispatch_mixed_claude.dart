import '../scenario.dart';
import 'ping_pong_mixed_claude.dart';

const _bus = 'mcp__teammate-bus__';

const doorbellDispatchLeaderKickoff = 'Dispatch work to the worker.';
const doorbellDispatchWorkerKickoff = 'Stand by at the prompt.';

/// Worker ends turn at prompt (no initial wait); leader `add_tasks` doorbells;
/// worker then parks on `wait_for_message` and auto-claims.
ScenarioRegistry doorbellDispatchMixedClaudeScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_list', name: '${_bus}list_teammates', input: {}),
      ToolUseTurn(
        id: 'tu_add',
        name: '${_bus}add_tasks',
        input: {
          'tasks': [
            {
              'title': 'doorbell-widget',
              'brief': 'Claim after task doorbell while at prompt.',
            },
          ],
        },
      ),
      ToolUseTurn(
        id: 'tu_list_claimed',
        name: '${_bus}list_tasks',
        input: {'status': 'claimed'},
      ),
      const TextTurn('dispatched'),
    ],
  ),
  workerScriptApiKey: MockScenario(
    turns: [
      const TextTurn('ready at prompt'),
      ToolUseTurn(
        id: 'tu_wait_task',
        name: '${_bus}wait_for_message',
        input: {},
      ),
      const TextTurn('claimed'),
    ],
  ),
});

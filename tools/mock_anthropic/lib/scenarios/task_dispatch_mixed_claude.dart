import '../scenario.dart';
import 'ping_pong_mixed_claude.dart';

/// Claude Code registers teammate-bus MCP tools as `mcp__<server>__<tool>`.
const _bus = 'mcp__teammate-bus__';

/// Kickoff strings submitted via PTY in L2 tests (see [MixedTeamTaskDispatchScenario]).
const taskDispatchLeaderKickoff = 'Dispatch work to the worker.';
const taskDispatchWorkerKickoff = 'Start idle loop.';

/// Leader parks on `wait_for_message` when doorbelled (no `add_tasks`).
///
/// Use for worker-only kickoff tests: worker idle-notify must not enqueue tasks
/// on the leader before the test asserts a stable SSE park.
ScenarioRegistry taskDispatchWorkerParkOnlyScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_wait', name: '${_bus}wait_for_message', input: {}),
    ],
  ),
  workerScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_wait', name: '${_bus}wait_for_message', input: {}),
      ToolUseTurn(
        id: 'tu_wait_task',
        name: '${_bus}wait_for_message',
        input: {},
      ),
      const TextTurn('claimed'),
    ],
  ),
});

/// Leader enqueues one task; worker parks on `wait_for_message` and auto-claims.
ScenarioRegistry taskDispatchMixedClaudeScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_list', name: '${_bus}list_teammates', input: {}),
      ToolUseTurn(
        id: 'tu_add',
        name: '${_bus}add_tasks',
        input: {
          'tasks': [
            {
              'title': 'ship-widget',
              'brief': 'Implement POST /widgets for the widget API.',
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
      ToolUseTurn(id: 'tu_wait', name: '${_bus}wait_for_message', input: {}),
      ToolUseTurn(
        id: 'tu_wait_task',
        name: '${_bus}wait_for_message',
        input: {},
      ),
      const TextTurn('claimed'),
    ],
  ),
});

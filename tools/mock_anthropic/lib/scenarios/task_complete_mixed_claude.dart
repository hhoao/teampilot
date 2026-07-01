import '../scenario.dart';
import 'ping_pong_mixed_claude.dart';

const _bus = 'mcp__teammate-bus__';

const taskCompleteLeaderKickoff = 'Dispatch work and wait for completion.';
const taskCompleteWorkerKickoff = 'Start idle loop.';

/// Leader enqueues; worker claims, reports `update_task(done)`; leader lists done.
ScenarioRegistry taskCompleteMixedClaudeScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_list', name: '${_bus}list_teammates', input: {}),
      ToolUseTurn(
        id: 'tu_add',
        name: '${_bus}add_tasks',
        input: {
          'tasks': [
            {
              'title': 'complete-widget',
              'brief': 'Ship the widget API and mark the task done.',
            },
          ],
        },
      ),
      ToolUseTurn(
        id: 'tu_list_done',
        name: '${_bus}list_tasks',
        input: {'status': 'done'},
      ),
      const TextTurn('completed'),
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
      AssignedTaskUpdateTurn(
        id: 'tu_done',
        toolName: '${_bus}update_task',
        status: 'done',
        result: 'widget API shipped',
      ),
      const TextTurn('reported'),
    ],
  ),
});

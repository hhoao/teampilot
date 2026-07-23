import '../core/turns.dart';
import 'ping_pong_mixed_claude.dart';

const taskCompleteLeaderKickoff = 'Dispatch work and wait for completion.';
const taskCompleteWorkerKickoff = 'Start idle loop.';

/// Leader enqueues; worker claims, reports `update_task(done)`; leader lists done.
Map<String, MockScenario> taskCompleteMixedClaudeScenarios() => {
      leadScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_list',
            toolRef: 'teambus.list_teammates',
            input: {},
          ),
          ToolUseTurn(
            id: 'tu_add',
            toolRef: 'teambus.add_tasks',
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
            toolRef: 'teambus.list_tasks',
            input: {'status': 'done'},
          ),
          ToolUseTurn(
            id: 'tu_wait',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
        ],
      ),
      workerScriptApiKey: MockScenario(
        turns: [
          // Single wait: parks until add_tasks is claimable. A cushion wait
          // races when the task lands on the first wait — the second wait then
          // blocks until MCP cancel and update_task never runs in time.
          ToolUseTurn(
            id: 'tu_wait_task',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          AssignedTaskUpdateTurn(
            id: 'tu_done',
            toolRef: 'teambus.update_task',
            status: 'done',
            result: 'widget API shipped',
          ),
          const TextTurn('reported'),
          ToolUseTurn(
            id: 'tu_wait_after_done',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
        ],
      ),
    };

import '../scenario.dart';
import 'ping_pong_mixed_claude.dart';

const _bus = 'mcp__teammate-bus__';

const mailPriorityLeaderKickoff = 'Enqueue work then send urgent mail.';
const mailPriorityWorkerKickoff = 'Start idle loop.';

/// Leader sends mail **before** enqueueing so a parked worker cannot claim the
/// task in the gap between separate Claude API rounds (L2 repro).
ScenarioRegistry mailPriorityMixedClaudeScenarios() => ScenarioRegistry({
  leadScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_list', name: '${_bus}list_teammates', input: {}),
      ToolUseTurn(
        id: 'tu_send',
        name: '${_bus}send_message',
        input: {'to': 'worker-1', 'content': 'urgent: pause work'},
      ),
      ToolUseTurn(
        id: 'tu_add',
        name: '${_bus}add_tasks',
        input: {
          'tasks': [
            {
              'title': 'orphan-task',
              'brief': 'Held until the urgent mail is consumed.',
            },
          ],
        },
      ),
      ToolUseTurn(
        id: 'tu_read',
        name: '${_bus}read_messages',
        input: {'unread_only': true},
      ),
      const TextTurn('coordinated'),
    ],
  ),
  workerScriptApiKey: MockScenario(
    turns: [
      ToolUseTurn(id: 'tu_wait_mail', name: '${_bus}wait_for_message', input: {}),
      ToolUseTurn(
        id: 'tu_reply',
        name: '${_bus}send_message',
        input: {'to': 'team-lead', 'content': 'copy that'},
      ),
      // L2 simultaneous kickoff: first wait may return before mail; second wait
      // consumes mail; third wait auto-claims the queued task.
      ToolUseTurn(id: 'tu_wait_mail2', name: '${_bus}wait_for_message', input: {}),
      ToolUseTurn(id: 'tu_wait_task', name: '${_bus}wait_for_message', input: {}),
      const TextTurn('done'),
    ],
  ),
});

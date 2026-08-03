import '../core/turns.dart';
import 'ping_pong_mixed_claude.dart';

const mailPriorityLeaderKickoff = 'Enqueue work then send urgent mail.';
const mailPriorityWorkerKickoff = 'Start idle loop.';

/// Leader sends mail **before** enqueueing so a parked worker cannot claim the
/// task in the gap between separate Claude API rounds (L2 repro).
Map<String, MockScenario> mailPriorityMixedClaudeScenarios() => {
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
            input: {'to': 'developer', 'content': 'urgent: pause work'},
          ),
          ToolUseTurn(
            id: 'tu_add',
            toolRef: 'teambus.add_tasks',
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
            toolRef: 'teambus.read_messages',
            input: {'unread_only': true},
          ),
          const TextTurn('coordinated'),
        ],
      ),
      workerScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_wait_mail',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          ToolUseTurn(
            id: 'tu_reply',
            toolRef: 'teambus.send_message',
            input: {'to': 'team-lead', 'content': 'copy that'},
          ),
          // L2 simultaneous kickoff: first wait may return before mail; second wait
          // consumes mail; third wait auto-claims the queued task.
          ToolUseTurn(
            id: 'tu_wait_mail2',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          ToolUseTurn(
            id: 'tu_wait_task',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          const TextTurn('done'),
        ],
      ),
    };

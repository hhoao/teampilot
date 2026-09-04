import '../core/turns.dart';
import 'ping_pong_mixed_claude.dart';

const doorbellMaterializeLeaderKickoff =
    'Greet the developer (lazy-spawned worker).';

const doorbellMaterializeMail = 'hello-via-materialize-doorbell';
const doorbellMaterializeAck = 'materialized-ack';

/// Lead sends to a still-declared worker → materialize funnel + mail doorbell
/// on the fresh PTY (no prior worker kickoff / wait_for_message park).
///
/// Worker first user input is the TeamBus mail doorbell; it must
/// `read_messages` then ack. Covers the path unit tests alone cannot:
/// spawn → surface defer → retry re-paste → consume.
Map<String, MockScenario> doorbellMaterializeMixedClaudeScenarios() => {
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
            input: {
              'to': 'developer',
              'content': doorbellMaterializeMail,
            },
          ),
          ToolUseTurn(
            id: 'tu_wait_ack',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          const TextTurn('done'),
        ],
      ),
      workerScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_read_mail',
            toolRef: 'teambus.read_messages',
            // The doorbell notice asks for mark_read so the inbox drains.
            input: {'unread_only': true, 'mark_read': true},
          ),
          ToolUseTurn(
            id: 'tu_ack',
            toolRef: 'teambus.send_message',
            input: {
              'to': 'team-lead',
              'content': doorbellMaterializeAck,
            },
          ),
          const TextTurn('done'),
        ],
      ),
    };

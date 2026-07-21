import '../core/turns.dart';

/// Actor apiKey for the team lead seat.
const leadScriptApiKey = 'lead-script';

/// Actor apiKey for the team worker seat.
const workerScriptApiKey = 'worker-script';

/// Stable markers asserted by L2 on the compose seat (lead) and worker PTY.
const markLead1 = 'MARK_LEAD_1';
const markLead2 = 'MARK_LEAD_2';
const markLeadDone = 'MARK_LEAD_DONE';
const markWorker1 = 'MARK_WORKER_1';

/// Mixed-mode TeamBus ping/pong with ≥3 lead assistant texts.
///
/// Logical `teambus.*` toolRefs (NOT raw `mcp__…` wire names). Wire mapping is
/// applied later via [CliTestProfile.toolName] / [ToolNameResolver].
///
/// L2 History compose targets the **lead** seat (`lead-script`): after the bus
/// exchange the lead script emits MARK_LEAD_1 / MARK_LEAD_2 / MARK_LEAD_DONE so
/// the lead thread can show ≥3 assistant bubbles.
Map<String, MockScenario> mixedCollab3PlusScenarios() => {
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
          TextTurn(markLead1),
          // Wait for worker pong (second wait semantics match ping_pong_mixed).
          ToolUseTurn(
            id: 'tu_wait_pong',
            toolRef: 'teambus.wait_for_message',
            input: {},
          ),
          TextTurn(markLead2),
          TextTurn(markLeadDone),
        ],
      ),
      workerScriptApiKey: MockScenario(
        turns: [
          // Single wait: kickoff parks here until the lead's ping arrives.
          // (A prior empty+second-wait pattern races when ping lands on the
          // first wait — worker never reaches send_message/pong.)
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
          TextTurn(markWorker1),
        ],
      ),
    };

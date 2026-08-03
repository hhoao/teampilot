import '../core/turns.dart';
import 'mixed_collab_3plus.dart' show leadScriptApiKey, workerScriptApiKey;

/// Stable markers for replicated native roster L2 (developer-0 / developer-1 pods).
const markReplicaLead1 = 'MARK_REPLICA_LEAD_1';
const markReplicaW01 = 'MARK_REPLICA_W0_1';
const markReplicaLead2 = 'MARK_REPLICA_LEAD_2';

/// Replicated native-team collab recipe (Claude / flashskyai L2).
///
/// Logical `native.*` toolRefs are placeholders for CLI-native swarm tools.
/// Profile `toolName` maps them to on-wire names, e.g.:
/// - `native.TeamCreate` → `TeamCreate`
/// - `native.TaskCreate` → `TaskCreate`
/// - `native.SendMessage` → `SendMessage`
/// (also: TaskList, TaskGet as needed)
///
/// Shape: lead dispatches to pod `developer-0` → worker-0 replies → lead
/// second compose confirms continued channel. `developer-1` stays idle (no
/// scenario key).
///
/// L2 History compose targets the **lead** seat (`lead-script`). Each lead
/// [TextTurn] is `end_turn` (native has no mixed Stop-hook chain), so the
/// Claude native cell advances one tool→text segment per History compose:
/// TaskCreate/SendMessage→MARK_REPLICA_LEAD_1, TaskList→MARK_REPLICA_LEAD_2.
///
/// Do **not** call TeamCreate here — TeamPilot already materializes the session
/// roster under [AppSession.cliTeamName]; a synthetic team_name would route
/// SendMessage to the wrong `teams/<name>/inboxes/` tree.
///
/// Pod addressing uses `developer-0` (not bare `developer`). Worker script
/// (`worker-script`) is consumed by pod `developer-0` via the shared
/// `mock-worker` provider; `developer-1` must not steal turns.
Map<String, MockScenario> nativeCollabReplica2PlusScenarios() => {
      leadScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_task_create',
            toolRef: 'native.TaskCreate',
            input: {
              'subject': 'Handle dispatched pod work.',
              'description': 'Assigned to developer-0 pod.',
            },
          ),
          ToolUseTurn(
            id: 'tu_send_dispatch',
            toolRef: 'native.SendMessage',
            input: {
              'to': 'developer-0',
              'message': 'Please handle the assigned task.',
              'summary': 'Handle assigned pod work',
            },
          ),
          TextTurn(markReplicaLead1),
          ToolUseTurn(
            id: 'tu_task_list',
            toolRef: 'native.TaskList',
            input: {},
          ),
          TextTurn(markReplicaLead2),
        ],
      ),
      workerScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_task_get',
            toolRef: 'native.TaskGet',
            input: {},
          ),
          TextTurn(markReplicaW01),
          ToolUseTurn(
            id: 'tu_reply',
            toolRef: 'native.SendMessage',
            input: {
              'to': 'team-lead',
              'message': 'reply',
              'summary': 'Worker reply',
            },
          ),
        ],
      ),
    };

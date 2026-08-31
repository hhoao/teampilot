import '../core/turns.dart';
import 'mixed_collab_3plus.dart'
    show
        leadScriptApiKey,
        markLead1,
        markLead2,
        markLeadDone,
        markWorker1,
        workerScriptApiKey;

/// Native-team collab recipe (Claude / flashskyai only in L2).
///
/// Logical `native.*` toolRefs are placeholders for CLI-native swarm tools.
/// Profile `toolName` maps them to on-wire names, e.g.:
/// - `native.TeamCreate` → `TeamCreate`
/// - `native.TaskCreate` → `TaskCreate`
/// - `native.TaskList` → `TaskList`
/// - `native.TaskStop` → `TaskStop`
/// (also: SendMessage, TaskGet, TaskUpdate, TaskOutput as needed)
///
/// Shape: lead dispatch → worker reply → lead close-out, with ≥3 lead texts.
///
/// L2 History compose targets the **lead** seat (`lead-script`). Each lead
/// [TextTurn] is `end_turn` (native has no mixed Stop-hook chain), so the
/// Claude native cell advances one tool→text segment per History compose:
/// TeamCreate/TaskCreate→MARK_LEAD_1, TaskList→MARK_LEAD_2,
/// TaskGet→MARK_LEAD_DONE.
Map<String, MockScenario> nativeCollab3PlusScenarios() => {
      leadScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_team_create',
            toolRef: 'native.TeamCreate',
            input: {'team_name': 'native-collab'},
          ),
          ToolUseTurn(
            id: 'tu_task_create',
            toolRef: 'native.TaskCreate',
            input: {
              'subject': 'developer',
              'description': 'Handle dispatched work.',
            },
          ),
          TextTurn(markLead1),
          ToolUseTurn(
            id: 'tu_task_list',
            toolRef: 'native.TaskList',
            input: {},
          ),
          TextTurn(markLead2),
          ToolUseTurn(
            id: 'tu_task_get',
            toolRef: 'native.TaskGet',
            input: {},
          ),
          TextTurn(markLeadDone),
        ],
      ),
      workerScriptApiKey: MockScenario(
        turns: [
          ToolUseTurn(
            id: 'tu_task_get',
            toolRef: 'native.TaskGet',
            input: {},
          ),
          TextTurn(markWorker1),
          ToolUseTurn(
            id: 'tu_task_update',
            toolRef: 'native.TaskUpdate',
            input: {'status': 'completed', 'result': 'done'},
          ),
          ToolUseTurn(
            id: 'tu_reply',
            toolRef: 'native.SendMessage',
            input: {'to': 'team-lead', 'content': 'reply'},
          ),
        ],
      ),
    };

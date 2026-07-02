import '../tools/add_tasks_tool.dart';
import '../tools/claim_task_tool.dart';
import '../tools/fetch_artifact_tool.dart';
import '../tools/list_artifacts_tool.dart';
import '../tools/list_tasks_tool.dart';
import '../tools/list_teammates_tool.dart';
import '../tools/publish_artifact_tool.dart';
import '../tools/read_messages_tool.dart';
import '../tools/send_message_tool.dart';
import '../tools/update_task_tool.dart';
import '../tools/wait_for_message_tool.dart';
import 'teammate_bus_tool.dart';
import 'teammate_bus_tool_context.dart';
import 'teammate_bus_tool_name.dart';

/// Core teammate-bus tools always available on `tools/list`.
const coreTeammateBusTools = <TeammateBusTool>[
  ListTeammatesTool(),
  SendMessageTool(),
  ReadMessagesTool(),
  WaitForMessageTool(),
];

/// Work-queue tools (mixed mode; gated via [TeammateBusTool.isEnabled]).
const taskQueueTeammateBusTools = <TeammateBusTool>[
  AddTasksTool(),
  UpdateTaskTool(),
  ListTasksTool(),
  ClaimTaskTool(),
];

/// Cross-machine artifact tools (gated via [TeammateBusTool.isEnabled]).
const artifactTeammateBusTools = <TeammateBusTool>[
  PublishArtifactTool(),
  ListArtifactsTool(),
  FetchArtifactTool(),
];

const allTeammateBusTools = <TeammateBusTool>[
  ...coreTeammateBusTools,
  ...taskQueueTeammateBusTools,
  ...artifactTeammateBusTools,
];

/// Tools advertised and dispatchable for the current handler capabilities.
Iterable<TeammateBusTool> enabledTeammateBusTools(
  TeammateBusToolContext ctx,
) =>
    allTeammateBusTools.where((tool) => tool.isEnabled(ctx));

Map<TeammateBusToolName, TeammateBusTool> teammateBusToolByName(
  TeammateBusToolContext ctx,
) =>
    {
      for (final tool in enabledTeammateBusTools(ctx)) tool.name: tool,
    };

/// Build the `tools/list` payload for the current handler capabilities.
List<Map<String, Object?>> listAdvertisedTeammateBusTools(
  TeammateBusToolContext ctx,
) =>
    [for (final tool in enabledTeammateBusTools(ctx)) tool.toJson()];

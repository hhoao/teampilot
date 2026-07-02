import 'add_tasks_tool.dart';
import 'claim_task_tool.dart';
import 'fetch_artifact_tool.dart';
import 'list_artifacts_tool.dart';
import 'list_tasks_tool.dart';
import 'list_teammates_tool.dart';
import 'mcp_tool_def.dart';
import 'publish_artifact_tool.dart';
import 'read_messages_tool.dart';
import 'send_message_tool.dart';
import 'update_task_tool.dart';
import 'wait_for_message_tool.dart';

/// Core teammate-bus tools always advertised on `tools/list`.
final coreTeammateBusTools = <McpToolDef>[
  ListTeammatesTool.def,
  SendMessageTool.def,
  ReadMessagesTool.def,
  WaitForMessageTool.def,
];

/// Work-queue tools (mixed mode; gated on [TeamBus.hasTaskQueue]).
final taskQueueTeammateBusTools = <McpToolDef>[
  AddTasksTool.def,
  UpdateTaskTool.def,
  ListTasksTool.def,
  ClaimTaskTool.def,
];

/// Cross-machine artifact tools (gated on artifact transfer service).
final artifactTeammateBusTools = <McpToolDef>[
  PublishArtifactTool.def,
  ListArtifactsTool.def,
  FetchArtifactTool.def,
];

/// Build the `tools/list` payload for the current handler capabilities.
List<Map<String, Object?>> listAdvertisedTeammateBusTools({
  required bool hasTaskQueue,
  required bool hasArtifacts,
}) =>
    [
      for (final tool in coreTeammateBusTools) tool.toJson(),
      if (hasTaskQueue)
        for (final tool in taskQueueTeammateBusTools) tool.toJson(),
      if (hasArtifacts)
        for (final tool in artifactTeammateBusTools) tool.toJson(),
    ];

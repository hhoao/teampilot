import '../../tasks/team_task.dart';
import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_context.dart';
import '../toolkit/teammate_bus_tool_name.dart';

final class AddTasksTool extends TeammateBusTool {
  const AddTasksTool();

  static const tasks = 'tasks';
  static const title = 'title';
  static const brief = 'brief';
  static const dependsOn = 'depends_on';
  static const requiredCapabilities = 'required_capabilities';
  static const preferredCapabilities = 'preferred_capabilities';
  static const preferredAssignee = 'preferred_assignee';

  static final _taskItemSchema = {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      title: McpSchema.string,
      brief: McpSchema.string,
      dependsOn: McpSchema.array(items: McpSchema.string),
      requiredCapabilities: McpSchema.array(items: McpSchema.string),
      preferredCapabilities: McpSchema.array(items: McpSchema.string),
      preferredAssignee: McpSchema.string,
    },
    'required': [title, brief],
  };

  @override
  TeammateBusToolName get name => TeammateBusToolName.addTasks;

  @override
  bool isEnabled(TeammateBusToolContext ctx) => ctx.bus.hasTaskQueue;

  @override
  String get description =>
      'Leader: enqueue tasks onto the shared work queue. Idle workers '
      'receive them automatically via their own wait_for_message (FIFO, '
      'deps-gated, auto-claimed). Each task: title (one line), brief (full '
      'instructions), optional depends_on (task ids that must be done '
      'first). Optionally route by capability: required_capabilities (hard '
      'filter — only members with all of them claim it), '
      'preferred_capabilities (ranking among eligible), and '
      'preferred_assignee (member id given first dibs).';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object(
    properties: {tasks: McpSchema.array(items: _taskItemSchema)},
    required: [tasks],
  );

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    final unavailable = call.taskQueueUnavailable();
    if (unavailable != null) return unavailable;

    final raw = call.arguments[tasks];
    final drafts = <TeamTaskDraft>[
      for (final item in (raw is List ? raw : const []))
        if (item is Map)
          TeamTaskDraft(
            title: item[title] as String? ?? '',
            brief: item[brief] as String? ?? '',
            dependsOn: [
              for (final dependency in (item[dependsOn] as List?) ?? const [])
                if (dependency is String) dependency,
            ],
            requiredCapabilities: {
              for (final capability
                  in (item[requiredCapabilities] as List?) ?? const [])
                if (capability is String && capability.trim().isNotEmpty)
                  capability.trim(),
            },
            preferredCapabilities: {
              for (final capability
                  in (item[preferredCapabilities] as List?) ?? const [])
                if (capability is String && capability.trim().isNotEmpty)
                  capability.trim(),
            },
            preferredAssignee:
                ((item[preferredAssignee] as String?)?.trim() ?? '').isEmpty
                ? null
                : (item[preferredAssignee] as String).trim(),
          ),
    ];
    final created = call.bus.addTasks(call.memberId, drafts);
    return call.ok(
      'Enqueued ${created.length} task(s):\n'
      '${created.map((task) => '- ${task.id}: ${task.title}').join('\n')}',
    );
  }
}

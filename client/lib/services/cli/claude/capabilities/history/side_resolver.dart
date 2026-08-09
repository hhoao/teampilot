import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';
import 'compatible_side_resolver.dart';
import 'workflow_resolver.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';

/// Claude history side resolver: regular `agent`/`task` sub-agents resolve via
/// [ClaudeCompatibleSideResolver]; `Workflow` orchestration runs resolve via
/// [ClaudeWorkflowResolver].
final class ClaudeSideResolver implements SubagentSideResolver {
  const ClaudeSideResolver({
    this.compatible = const ClaudeCompatibleSideResolver(),
    this.workflow = const ClaudeWorkflowResolver(),
  });

  final ClaudeCompatibleSideResolver compatible;
  final ClaudeWorkflowResolver workflow;

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) {
    if (isWorkflowTool(part.toolName)) {
      return workflow.resolve(
        part: part,
        ctx: ctx,
        parentTranscriptPath: _parentTranscriptPath(
          parentHandle,
          rootTranscriptPath,
        ),
      );
    }
    return compatible.resolve(
      part: part,
      ctx: ctx,
      parentHandle: parentHandle,
      rootTranscriptPath: rootTranscriptPath,
      toolCallAt: toolCallAt,
    );
  }

  static String? _parentTranscriptPath(
    SubagentSideHandle? parentHandle,
    String? rootTranscriptPath,
  ) {
    if (parentHandle is SubagentFileHandle) {
      final path = parentHandle.path.trim();
      if (path.isNotEmpty) return path;
    }
    final root = rootTranscriptPath?.trim();
    if (root != null && root.isNotEmpty) return root;
    return null;
  }
}

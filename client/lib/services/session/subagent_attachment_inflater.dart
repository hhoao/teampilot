import 'package:ai_message_core/ai_message_core.dart';

import '../../utils/logging/logger.dart';
import '../cli/registry/capabilities/ai_history_capability.dart';
import 'session_history_context.dart';

class SubagentAttachmentInflater {
  const SubagentAttachmentInflater({this.maxDepth = 8});

  final int maxDepth;

  Future<Map<String, AiSubagentAttachment>> inflate({
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required AiHistoryCapability capability,
    required String? rootTranscriptPath,
  }) async {
    final out = <String, AiSubagentAttachment>{};
    await _walk(
      messages: messages,
      ctx: ctx,
      capability: capability,
      rootTranscriptPath: rootTranscriptPath,
      parentHandle: null,
      depth: 0,
      out: out,
    );
    return out;
  }

  /// Resolves one root-level subagent tool call (depth zero). Workflow child
  /// ids are handled by [resolveByToolCallId].
  Future<AiSubagentAttachment> inflateOne({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required AiHistoryCapability capability,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) {
    return _attachOne(
      part: part,
      toolCallAt: toolCallAt,
      ctx: ctx,
      capability: capability,
      rootTranscriptPath: rootTranscriptPath,
      parentHandle: null,
      depth: 0,
    );
  }

  /// Resolves a single attachment by [toolCallId], including workflow fan-out
  /// child ids. Returns null when the id is not a known subagent tool call.
  Future<AiSubagentAttachment?> resolveByToolCallId({
    required String toolCallId,
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required AiHistoryCapability capability,
    required String? rootTranscriptPath,
  }) async {
    final id = toolCallId.trim();
    if (id.isEmpty) return null;

    for (final message in messages) {
      for (final part in message.parts) {
        if (part is! AiToolCallPart) continue;
        if (part.toolCallId.trim() != id) continue;
        final name = part.toolName.trim().toLowerCase();
        if (!capability.subagentToolNames.contains(name)) continue;
        return inflateOne(
          part: part,
          toolCallAt: message.createdAt,
          ctx: ctx,
          capability: capability,
          rootTranscriptPath: rootTranscriptPath,
        );
      }
    }

    for (final message in messages) {
      for (final part in message.parts) {
        if (part is! AiToolCallPart) continue;
        if (part.toolName.trim().toLowerCase() != 'workflow') continue;
        final parent = await inflateOne(
          part: part,
          toolCallAt: message.createdAt,
          ctx: ctx,
          capability: capability,
          rootTranscriptPath: rootTranscriptPath,
        );
        final children = <String, AiSubagentAttachment>{};
        _addWorkflowChildren(parent, children);
        return children[id];
      }
    }
    return null;
  }

  static void addWorkflowChildren(
    AiSubagentAttachment attachment,
    Map<String, AiSubagentAttachment> out,
  ) => _addWorkflowChildren(attachment, out);

  static void _addWorkflowChildren(
    AiSubagentAttachment attachment,
    Map<String, AiSubagentAttachment> out,
  ) {
    final workflow = attachment.workflow;
    if (workflow == null) return;
    for (final agent in workflow.agents) {
      final childId = subagentWorkflowChildToolCallId(
        workflow.runId,
        agent.agentId,
      );
      if (out.containsKey(childId)) continue;
      out[childId] = AiSubagentAttachment(
        toolCallId: childId,
        messages: agent.messages,
        source: AiSubagentAttachmentSource.sideTranscript,
        title: agent.role,
        handle: agent.handle,
      );
    }
  }

  Future<void> _walk({
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required AiHistoryCapability capability,
    required String? rootTranscriptPath,
    required SubagentSideHandle? parentHandle,
    required int depth,
    required Map<String, AiSubagentAttachment> out,
  }) async {
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is! AiToolCallPart) continue;
        final name = part.toolName.trim().toLowerCase();
        if (!capability.subagentToolNames.contains(name)) continue;
        if (part.toolCallId.trim().isEmpty) continue;
        if (out.containsKey(part.toolCallId)) continue;

        final attachment = await _attachOne(
          part: part,
          toolCallAt: message.createdAt,
          ctx: ctx,
          capability: capability,
          rootTranscriptPath: rootTranscriptPath,
          parentHandle: parentHandle,
          depth: depth,
        );
        out[part.toolCallId] = attachment;

        if (depth >= maxDepth) continue;

        final workflow = attachment.workflow;
        if (workflow != null) {
          // A Workflow run fans out into one preview entry per agent; each
          // agent transcript may itself nest further sub-agents.
          _addWorkflowChildren(attachment, out);
          for (final agent in workflow.agents) {
            final childId = subagentWorkflowChildToolCallId(
              workflow.runId,
              agent.agentId,
            );
            final child = out[childId];
            if (child == null) continue;
            await _walk(
              messages: child.messages,
              ctx: ctx,
              capability: capability,
              rootTranscriptPath: rootTranscriptPath,
              parentHandle: child.handle,
              depth: depth + 1,
              out: out,
            );
          }
        } else {
          await _walk(
            messages: attachment.messages,
            ctx: ctx,
            capability: capability,
            rootTranscriptPath: rootTranscriptPath,
            parentHandle: attachment.handle,
            depth: depth + 1,
            out: out,
          );
        }
      }
    }
  }

  Future<AiSubagentAttachment> _attachOne({
    required AiToolCallPart part,
    required DateTime? toolCallAt,
    required SessionHistoryContext ctx,
    required AiHistoryCapability capability,
    required String? rootTranscriptPath,
    required SubagentSideHandle? parentHandle,
    required int depth,
  }) async {
    final title = subagentTitleFromPart(part);

    if (depth >= maxDepth) {
      return _degrade(part, title);
    }

    try {
      final resolved = await capability.subagentSideResolver.resolve(
        part: part,
        ctx: ctx,
        parentHandle: parentHandle,
        rootTranscriptPath: rootTranscriptPath,
        toolCallAt: toolCallAt,
      );
      if (resolved != null) {
        return AiSubagentAttachment(
          toolCallId: part.toolCallId,
          messages: resolved.messages,
          source: AiSubagentAttachmentSource.sideTranscript,
          title: title,
          handle: resolved.handle,
          workflow: resolved.workflow,
        );
      }
    } catch (e, st) {
      appLogger.w(
        '[subagent-inflate] resolve failed toolCallId=${part.toolCallId}: $e',
        error: e,
        stackTrace: st,
      );
    }

    return _degrade(part, title);
  }

  AiSubagentAttachment _degrade(AiToolCallPart part, String? title) {
    return AiSubagentAttachment(
      toolCallId: part.toolCallId,
      messages: syntheticSubagentMessagesFromResult(
        toolCallId: part.toolCallId,
        result: part.result,
      ),
      source: AiSubagentAttachmentSource.toolResult,
      title: title,
    );
  }
}

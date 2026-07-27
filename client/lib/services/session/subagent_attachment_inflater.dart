import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:path/path.dart' as p;

import '../cli/registry/capabilities/history/claude_compatible_jsonl.dart';
import '../io/filesystem.dart';
import 'subagent_side_transcript_path.dart';

class SubagentAttachmentInflater {
  const SubagentAttachmentInflater({this.maxDepth = 8});

  final int maxDepth;

  Future<Map<String, AiSubagentAttachment>> inflate({
    required List<AiMessage> messages,
    required Filesystem fs,
    required String? parentTranscriptPath,
  }) async {
    final out = <String, AiSubagentAttachment>{};
    await _walk(
      messages: messages,
      fs: fs,
      parentTranscriptPath: parentTranscriptPath,
      depth: 0,
      out: out,
    );
    return out;
  }

  Future<void> _walk({
    required List<AiMessage> messages,
    required Filesystem fs,
    required String? parentTranscriptPath,
    required int depth,
    required Map<String, AiSubagentAttachment> out,
  }) async {
    final usableParent = _isUsableParentPath(parentTranscriptPath);
    final metaByToolUseId = usableParent
        ? await _loadMetaMap(fs, parentTranscriptPath!.trim())
        : const <String, String>{};

    for (final message in messages) {
      for (final part in message.parts) {
        if (part is! AiToolCallPart) continue;
        if (!isAiSubagentToolName(part.toolName)) continue;
        if (part.toolCallId.trim().isEmpty) continue;
        if (out.containsKey(part.toolCallId)) continue;

        final attachment = await _attachOne(
          part: part,
          fs: fs,
          parentTranscriptPath: usableParent ? parentTranscriptPath!.trim() : null,
          metaByToolUseId: metaByToolUseId,
          depth: depth,
        );
        out[part.toolCallId] = attachment;

        if (depth < maxDepth) {
          await _walk(
            messages: attachment.messages,
            fs: fs,
            parentTranscriptPath: attachment.sidePath,
            depth: depth + 1,
            out: out,
          );
        }
      }
    }
  }

  Future<AiSubagentAttachment> _attachOne({
    required AiToolCallPart part,
    required Filesystem fs,
    required String? parentTranscriptPath,
    required Map<String, String> metaByToolUseId,
    required int depth,
  }) async {
    final title = subagentTitleFromPart(part);

    if (depth >= maxDepth) {
      return _degrade(part, title);
    }

    final agentId =
        metaByToolUseId[part.toolCallId] ?? subagentAgentIdFromPart(part);
    if (agentId != null &&
        agentId.isNotEmpty &&
        _isUsableParentPath(parentTranscriptPath)) {
      final parentPath = parentTranscriptPath!.trim();
      final subagentsDir = claudeSubagentsDirFor(parentPath);
      final sidePath = claudeSubagentTranscriptPath(
        subagentsDir: subagentsDir,
        agentId: agentId,
      );
      final content = await fs.readString(sidePath);
      if (content != null) {
        final sideMessages = parseClaudeCompatibleJsonl(
          content,
          fallbackId: () => 'subagent-$agentId-${part.toolCallId}',
        );
        return AiSubagentAttachment(
          toolCallId: part.toolCallId,
          messages: sideMessages,
          source: AiSubagentAttachmentSource.sideTranscript,
          title: title,
          sidePath: sidePath,
        );
      }
    }

    return _degrade(part, title);
  }

  /// Blank / whitespace paths skip side FS (same as null).
  static bool _isUsableParentPath(String? path) =>
      path != null && path.trim().isNotEmpty;

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

  Future<Map<String, String>> _loadMetaMap(
    Filesystem fs,
    String parentTranscriptPath,
  ) async {
    final subagentsDir = claudeSubagentsDirFor(parentTranscriptPath);
    final map = <String, String>{};
    List<FsDirEntry> entries;
    try {
      entries = await fs.listDir(subagentsDir);
    } catch (_) {
      return map;
    }

    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final name = entry.name;
      if (!name.startsWith('agent-') || !name.endsWith('.meta.json')) {
        continue;
      }
      final agentId = name.substring(
        'agent-'.length,
        name.length - '.meta.json'.length,
      );
      if (agentId.isEmpty) continue;

      final metaPath = p.join(subagentsDir, name);
      final raw = await fs.readString(metaPath);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final toolUseId = decoded['toolUseId'];
        if (toolUseId is! String) continue;
        final trimmed = toolUseId.trim();
        if (trimmed.isEmpty) continue;
        map[trimmed] = agentId;
      } on FormatException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return map;
  }
}

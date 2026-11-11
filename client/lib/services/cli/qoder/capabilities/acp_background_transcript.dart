import 'package:ai_message_core/ai_message_core.dart';

import '../../../acp/projects_jsonl_background_transcript.dart';
import '../../claude/capabilities/history/compatible_jsonl.dart';

/// Incremental reader for a Qoder CLI session transcript.
///
/// Qoder writes the same `projects/<bucket>/<id>.jsonl` shape as the Claude
/// Code family, under the ACP session's isolated config dir (
/// `sessionToolDir`). The ACP wire goes silent after `end_turn`, so this is
/// the only way the app notices that a background task finished and the agent
/// resumed the conversation on its own.
final class QoderAcpBackgroundTranscriptSource
    extends ProjectsJsonlBackgroundTranscriptSource {
  QoderAcpBackgroundTranscriptSource({
    required super.fs,
    required super.sessionToolDir,
    required super.sessionId,
    String fallbackPrefix = 'qoder',
  }) : super(lineAppend: appendQoderJsonlEvent, fallbackPrefix: fallbackPrefix);
}

/// Parses one Qoder JSONL event, dropping agent-only system notices.
///
/// Qoder records the background-task completion as a `type: user` event with
/// `isMeta: true` and a `<task-notification>` body. It is also written to the
/// agent's own context, not typed by the operator, so rendering it as a user
/// bubble would be misleading. The assistant reply that follows is kept.
bool appendQoderJsonlEvent(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
}) {
  if (event['isMeta'] == true) return false;
  return appendClaudeJsonlEvent(messages, event, fallbackId: fallbackId);
}

import 'package:path/path.dart' as p;

/// Claude layout: `{parentStem}/subagents` beside the parent `.jsonl`.
String claudeSubagentsDirFor(String parentTranscriptPath) {
  return p.join(p.withoutExtension(parentTranscriptPath), 'subagents');
}

String claudeSubagentTranscriptPath({
  required String subagentsDir,
  required String agentId,
}) {
  return p.join(subagentsDir, 'agent-$agentId.jsonl');
}

String claudeSubagentMetaPath({
  required String subagentsDir,
  required String agentId,
}) {
  return p.join(subagentsDir, 'agent-$agentId.meta.json');
}

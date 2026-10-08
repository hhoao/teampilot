import 'package:path/path.dart' as p;

/// Pick a path style from [samplePath] so Windows hosts still resolve
/// POSIX transcript layouts (InMemoryFilesystem tests, SSH/remote roots).
p.Context pathContextForTranscript(String samplePath) {
  if (samplePath.contains(r'\')) return p.windows;
  return p.posix;
}

/// Claude layout: `{parentStem}/subagents` beside the parent `.jsonl`.
String claudeSubagentsDirFor(
  String parentTranscriptPath, {
  p.Context? pathContext,
}) {
  final path = pathContext ?? pathContextForTranscript(parentTranscriptPath);
  return path.join(path.withoutExtension(parentTranscriptPath), 'subagents');
}

String claudeSubagentTranscriptPath({
  required String subagentsDir,
  required String agentId,
  p.Context? pathContext,
}) {
  final path = pathContext ?? pathContextForTranscript(subagentsDir);
  return path.join(subagentsDir, 'agent-$agentId.jsonl');
}

String claudeSubagentMetaPath({
  required String subagentsDir,
  required String agentId,
  p.Context? pathContext,
}) {
  final path = pathContext ?? pathContextForTranscript(subagentsDir);
  return path.join(subagentsDir, 'agent-$agentId.meta.json');
}

/// Claude WorkFlow layout: run records `{parentStem}/workflows/wf_{runId}.json`
/// beside the parent transcript.
String claudeWorkflowsDirFor(
  String parentTranscriptPath, {
  p.Context? pathContext,
}) {
  final path = pathContext ?? pathContextForTranscript(parentTranscriptPath);
  return path.join(path.withoutExtension(parentTranscriptPath), 'workflows');
}

/// Claude WorkFlow run directory:
/// `{parentStem}/subagents/workflows/wf_{runId}/agent-*.jsonl`.
String claudeWorkflowRunDirFor(
  String parentTranscriptPath, {
  required String runId,
  p.Context? pathContext,
}) {
  final path = pathContext ?? pathContextForTranscript(parentTranscriptPath);
  return path.join(
    claudeSubagentsDirFor(parentTranscriptPath, pathContext: path),
    'workflows',
    runId,
  );
}

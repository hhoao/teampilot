import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/subagent_side_transcript_path.dart';

void main() {
  test('claude subagents dir + agent paths', () {
    expect(
      claudeSubagentsDirFor('/projects/enc/uuid.jsonl'),
      '/projects/enc/uuid/subagents',
    );
    expect(
      claudeSubagentTranscriptPath(subagentsDir: '/x/subagents', agentId: 'abc'),
      '/x/subagents/agent-abc.jsonl',
    );
    expect(
      claudeSubagentMetaPath(subagentsDir: '/x/subagents', agentId: 'abc'),
      '/x/subagents/agent-abc.meta.json',
    );
  });
}

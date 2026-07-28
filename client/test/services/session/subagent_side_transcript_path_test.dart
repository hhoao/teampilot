import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  test('windows-style parents keep backslash joins', () {
    expect(
      claudeSubagentsDirFor(r'C:\projects\enc\uuid.jsonl'),
      r'C:\projects\enc\uuid\subagents',
    );
    expect(
      pathContextForTranscript(r'C:\a\b'),
      p.windows,
    );
    expect(
      pathContextForTranscript('/projects/a'),
      p.posix,
    );
  });
}

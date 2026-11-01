import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_background_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp_background_transcript.dart';

import '../../../../support/in_memory_filesystem.dart';

const _sessionId = 'acp-session-1';
const _toolDir = '/sessions/s1/runtime/claude';

String _userLine(String text) => jsonEncode({
  'type': 'user',
  'message': {'role': 'user', 'content': text},
});

String _assistantLine(String text) => jsonEncode({
  'type': 'assistant',
  'message': {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
});

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  Future<void> writeTranscript(String content) async {
    await fs.ensureDir('$_toolDir/projects/-repo');
    await fs.writeString('$_toolDir/projects/-repo/$_sessionId.jsonl', content);
  }

  test('locates the transcript in any project bucket and parses it', () async {
    await writeTranscript(
      '${_userLine('run')}\n${_assistantLine('Started')}\n',
    );
    final source = ClaudeAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    final result = await source.refresh();

    expect(result, isNotNull);
    expect(result!.changed, isTrue);
    expect(result.messages, hasLength(2));
    expect(result.messages.first.role.name, 'user');
    expect(result.messages.last.role.name, 'assistant');
  });

  test('returns null when no transcript exists for the session', () async {
    await fs.ensureDir('$_toolDir/projects/-other');
    final source = ClaudeAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    expect(await source.refresh(), isNull);
  });

  test('reports no change until the transcript grows', () async {
    await writeTranscript('${_userLine('run')}\n');
    final source = ClaudeAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    final first = await source.refresh();
    expect(first?.changed, isTrue);
    expect(first?.messages, hasLength(1));

    final unchanged = await source.refresh();
    expect(unchanged?.changed, isFalse);

    await fs.appendString(
      '$_toolDir/projects/-repo/$_sessionId.jsonl',
      '${_assistantLine('All tests passed')}\n',
    );
    final grown = await source.refresh();
    expect(grown?.changed, isTrue);
    expect(grown?.messages, hasLength(2));
  });

  test('keeps the transcript readable for the cubit merge', () async {
    await writeTranscript('${_userLine('run')}\n');
    final source = ClaudeAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    final result = await source.refresh();

    expect(result, isA<AcpBackgroundTranscriptResult>());
    expect(result!.messages.first.parts, isNotEmpty);
  });

  test('Claude ACP capability exposes the transcript source', () async {
    const capability = ClaudeAcpCapability();

    final source = capability.createBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    expect(source, isA<ClaudeAcpBackgroundTranscriptSource>());
  });

  test('re-locates when the session moves to another project bucket', () async {
    await writeTranscript('${_userLine('run')}\n');
    final source = ClaudeAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    expect((await source.refresh())?.changed, isTrue);

    // A worktree move rewrites the bucket the transcript lives under.
    final moved = '$_toolDir/projects/-worktree';
    await fs.ensureDir(moved);
    await fs.rename(
      '$_toolDir/projects/-repo/$_sessionId.jsonl',
      '$moved/$_sessionId.jsonl',
    );
    await fs.appendString(
      '$moved/$_sessionId.jsonl',
      '${_assistantLine('Done')}\n',
    );

    final grown = await source.refresh();

    expect(grown?.changed, isTrue);
    expect(grown?.messages, hasLength(2));
  });
}

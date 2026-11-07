import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/capabilities/acp.dart';
import 'package:teampilot/services/cli/qoder/capabilities/acp_background_transcript.dart';

import '../../../../support/in_memory_filesystem.dart';

const _sessionId = 'dadf5397-6cc7-41bb-bf4f-e850a9cafb0f';
const _toolDir = '/sessions/s1/runtime/qoder';

String _userLine(String text) => jsonEncode({
  'type': 'user',
  'uuid': 'user-uuid',
  'message': {'role': 'user', 'content': text},
});

String _assistantLine(String text) => jsonEncode({
  'type': 'assistant',
  'uuid': 'assistant-uuid',
  'message': {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
});

String _backgroundToolLine() => jsonEncode({
  'type': 'assistant',
  'uuid': 'tool-uuid',
  'message': {
    'id': 'tool-message',
    'role': 'assistant',
    'content': [
      {
        'type': 'tool_use',
        'id': 'call_00_pk198isHwQmk1eyWqtZo1716',
        'name': 'Bash',
        'input': {
          'command': 'sleep 60',
          'description': 'Run a 1-minute background timer task',
          'run_in_background': true,
        },
      },
    ],
  },
});

String _taskNotificationLine() => jsonEncode({
  'type': 'user',
  'uuid': 'notification-uuid',
  'isMeta': true,
  'origin': {'kind': 'task-notification'},
  'message': {
    'role': 'user',
    'content': [
      {
        'type': 'text',
        'text':
            '[SYSTEM NOTIFICATION - NOT USER INPUT]\n'
            '<task-notification>\n'
            '<tool-use-id>call_00_pk198isHwQmk1eyWqtZo1716</tool-use-id>\n'
            '<status>completed</status>\n'
            '</task-notification>',
      },
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
    final source = QoderAcpBackgroundTranscriptSource(
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
    final source = QoderAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    expect(await source.refresh(), isNull);
  });

  test('reports no change until the transcript grows', () async {
    await writeTranscript('${_userLine('run')}\n');
    final source = QoderAcpBackgroundTranscriptSource(
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

  test('drops the meta task-notification row but keeps the reply', () async {
    await writeTranscript(
      '${_userLine('run')}\n'
      '${_backgroundToolLine()}\n'
      '${_taskNotificationLine()}\n'
      '${_assistantLine('Background task completed.')}\n',
    );
    final source = QoderAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    final result = await source.refresh();

    expect(result!.messages, hasLength(2));
    expect(
      result.messages.every(
        (message) => !message.parts.any(
          (part) =>
              part is AiTextPart && part.text.contains('<task-notification>'),
        ),
      ),
      isTrue,
    );
    expect(
      result.messages.last.parts.whereType<AiTextPart>().single.text,
      'Background task completed.',
    );
  });

  test('keeps background tool-call args for the cubit lease logic', () async {
    await writeTranscript('${_userLine('run')}\n${_backgroundToolLine()}\n');
    final source = QoderAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    final result = await source.refresh();

    final tool = result!.messages
        .expand((message) => message.parts)
        .whereType<AiToolCallPart>()
        .single;
    expect(tool.args?['run_in_background'], isTrue);
    expect(tool.args?['description'], 'Run a 1-minute background timer task');
  });

  test('Qoder ACP capability exposes the transcript source', () {
    const capability = QoderAcpCapability();

    final source = capability.createBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    expect(source, isA<QoderAcpBackgroundTranscriptSource>());
  });

  test('re-locates when the session moves to another project bucket', () async {
    await writeTranscript('${_userLine('run')}\n');
    final source = QoderAcpBackgroundTranscriptSource(
      fs: fs,
      sessionToolDir: _toolDir,
      sessionId: _sessionId,
    );

    expect((await source.refresh())?.changed, isTrue);

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

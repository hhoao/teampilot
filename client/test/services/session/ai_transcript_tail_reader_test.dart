import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/session/ai_transcript_tail_reader.dart';

import '../../support/in_memory_filesystem.dart';

EventDecoder _syncDecoder() {
  return (lines) async => [
        for (final line in lines)
          tryDecodeJsonlLine(utf8.decode(line, allowMalformed: true)),
      ];
}

AiTranscriptTailReader _reader() => AiTranscriptTailReader(
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      windowSizes: const [512, 2048], // 小窗口便于测试窗口扩展
      fullReloadEvery: 30,
    );

void main() {
  final fs = InMemoryFilesystem();
  const path = '/transcript.jsonl';

  String userLine(String id, String text) =>
      '{"type":"user","uuid":"$id","message":{"id":"$id","content":"$text"},"timestamp":"2026-08-10T00:00:00Z"}';
  String assistantLine(String id, String text) =>
      '{"type":"assistant","uuid":"$id","message":{"id":"$id","content":"$text"},"timestamp":"2026-08-10T00:00:00Z"}';
  String metaLine() =>
      '{"type":"last-prompt","lastPrompt":"x","sessionId":"s"}';

  test('append: only new lines are parsed; instance is reused', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);
    final first = state.messages;
    expect(
      first.map((m) => (m.parts.single as AiTextPart).text).toList(),
      ['hi'],
    );

    // 追加:新 user + 元数据行(不消费)+ 流式 assistant 分片
    await fs.appendString(
      path,
      '${metaLine()}\n${assistantLine('a1', 'part1 ')}\n${assistantLine('a1', 'part2')}\n',
    );
    await reader.refresh(fs: fs, path: path, state: state);
    expect(identical(state.messages, first), isTrue,
        reason: '消息列表必须原地变异,实例保持不变');
    expect(state.messages, hasLength(2));
    expect(
      (state.messages[1].parts.single as AiTextPart).text,
      'part1 part2',
      reason: '同 message.id 的流式分片必须合并',
    );
  });

  test('anchor missing after rewrite triggers full rebuild', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);

    // 模拟 compact:整个文件被重写(内容不同)
    await fs.writeString(
      path,
      '${userLine('u2', 'rewritten')}\n${assistantLine('a9', 'summary')}\n',
    );
    final result = await reader.refresh(fs: fs, path: path, state: state);
    expect(result.rebuilt, isTrue);
    expect(
      state.messages.map((m) => (m.parts.single as AiTextPart).text).toList(),
      ['rewritten', 'summary'],
    );
  });

  test('anchor outside small window expands to larger window', () async {
    final big = StringBuffer();
    for (var i = 0; i < 20; i++) {
      big.write(userLine('u$i', 'x' * 60));
      big.write('\n');
    }
    await fs.writeString(path, big.toString());
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);
    expect(state.messages, hasLength(20));

    await fs.appendString(path, '${assistantLine('tail', 'new')}\n');
    final result = await reader.refresh(fs: fs, path: path, state: state);
    expect(result.changed, isTrue);
    expect(state.messages, hasLength(21));
  });

  test('half-written trailing line is deferred until completed', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);

    await fs.appendString(path, '{"type":"assistant","uuid":"a1",');
    var result = await reader.refresh(fs: fs, path: path, state: state);
    expect(result.changed, isFalse);
    expect(state.messages, hasLength(1));

    await fs.appendString(path, '"message":{"id":"a1","content":"done"}}');
    await fs.appendString(path, '\n');
    result = await reader.refresh(fs: fs, path: path, state: state);
    expect(result.changed, isTrue);
    expect(state.messages, hasLength(2));
  });

  test('file shrink resets state', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);

    await fs.writeString(path, '${userLine('u2', 'small')}\n');
    final result = await reader.refresh(fs: fs, path: path, state: state);
    expect(result.rebuilt, isTrue);
    expect(
      state.messages.map((m) => (m.parts.single as AiTextPart).text).toList(),
      ['small'],
    );
  });

  test('fullReloadEvery triggers periodic full validation', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = AiTranscriptTailReader(
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      windowSizes: const [512, 2048],
      fullReloadEvery: 3,
    );
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);
    for (var i = 0; i < 3; i++) {
      await fs.appendString(path, '${assistantLine('a$i', 'm$i')}\n');
      await reader.refresh(fs: fs, path: path, state: state);
    }
    final result = await reader.refresh(fs: fs, path: path, state: state);
    expect(result.rebuilt, isTrue,
        reason: '第 4 次 refresh 累积 3 次增量后应触发全量校验');
    expect(state.messages, hasLength(4));
  });
}

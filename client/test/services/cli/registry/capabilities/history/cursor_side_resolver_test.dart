import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/side_resolver.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _root = '/projects/home/agent-transcripts';
const _parentId = 'parent-uuid';
const _parentPath = '$_root/$_parentId/$_parentId.jsonl';

SessionHistoryContext _ctx(Filesystem fs) => SessionHistoryContext(
  fs: fs,
  taskId: 'task-1',
  env: const {},
  transcriptRoots: const [],
  bucket: 'bucket',
);

Future<SubagentSideResolveResult?> _resolve({
  required Filesystem fs,
  required AiToolCallPart part,
  String? rootTranscriptPath,
  SubagentSideHandle? parentHandle,
  DateTime? toolCallAt,
}) {
  return const CursorSideResolver().resolve(
    part: part,
    ctx: _ctx(fs),
    parentHandle: parentHandle,
    rootTranscriptPath: rootTranscriptPath,
    toolCallAt: toolCallAt,
  );
}

String _cursorUserJsonl(String text) {
  return jsonEncode({
    'role': 'user',
    'message': {'content': text},
    'timestamp': '2026-07-28T10:00:00.000Z',
  });
}

String _cursorTranscript({required String firstUserText, String? assistant}) {
  final lines = <String>[_cursorUserJsonl(firstUserText)];
  if (assistant != null) {
    lines.add(
      jsonEncode({
        'role': 'assistant',
        'message': {'content': assistant},
        'timestamp': '2026-07-28T10:00:01.000Z',
      }),
    );
  }
  return '${lines.join('\n')}\n';
}

class _MtimeFilesystem extends InMemoryFilesystem {
  final Map<String, DateTime> mtimes = {};

  void setMtime(String path, DateTime mtime) => mtimes[path] = mtime;

  @override
  Future<FsStat> stat(String path) async {
    final base = await super.stat(path);
    if (!base.exists) return base;
    return FsStat(kind: base.kind, size: base.size, mtime: mtimes[path]);
  }
}

class _SubagentsGuardFilesystem extends _MtimeFilesystem {
  int subagentsReadAttempts = 0;

  @override
  Future<String?> readString(String path) async {
    if (path.contains('/subagents/')) {
      subagentsReadAttempts++;
      throw StateError('must not read subagents: $path');
    }
    return super.readString(path);
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    if (path.contains('/subagents/')) {
      subagentsReadAttempts++;
      throw StateError('must not read subagents: $path');
    }
    return super.readBytes(path);
  }
}

void main() {
  test('args.resume UUID resolves nested sibling transcript', () async {
    final fs = InMemoryFilesystem();
    const childId = 'child-resume-uuid';
    await fs.writeString(
      _parentPath,
      _cursorTranscript(firstUserText: 'parent turn'),
    );
    await fs.writeString(
      '$_root/$childId/$childId.jsonl',
      _cursorTranscript(firstUserText: 'resume child', assistant: 'done'),
    );

    final result = await _resolve(
      fs: fs,
      rootTranscriptPath: _parentPath,
      part: const AiToolCallPart(
        toolCallId: 'tool-1',
        toolName: 'Task',
        args: {'resume': childId, 'prompt': 'ignored when resume hits'},
      ),
    );

    expect(result, isNotNull);
    expect(result!.handle, isA<SubagentFileHandle>());
    expect(
      (result.handle as SubagentFileHandle).path,
      '$_root/$childId/$childId.jsonl',
    );
    expect(result.messages, isNotEmpty);
    expect(
      result.messages
          .where((m) => m.role == AiRole.user)
          .first
          .parts
          .whereType<AiTextPart>()
          .single
          .text,
      'resume child',
    );
  });

  test(
    'prompt heuristic matches normalized sibling and excludes parent stem',
    () async {
      final fs = _MtimeFilesystem();
      const childId = 'child-heuristic';
      final reference = DateTime.utc(2026, 7, 28, 12, 0);
      await fs.writeString(
        _parentPath,
        _cursorTranscript(firstUserText: 'parent-only prompt'),
      );
      fs.setMtime(_parentPath, reference);
      await fs.writeString(
        '$_root/$childId/$childId.jsonl',
        _cursorTranscript(
          firstUserText:
              '<timestamp>Tue Jul 28 2026</timestamp>\n'
              '<user_query>explore auth module</user_query>',
          assistant: 'found routes',
        ),
      );
      fs.setMtime(
        '$_root/$childId/$childId.jsonl',
        reference.add(const Duration(minutes: 2)),
      );

      final result = await _resolve(
        fs: fs,
        rootTranscriptPath: _parentPath,
        part: const AiToolCallPart(
          toolCallId: 'tool-2',
          toolName: 'Task',
          args: {'prompt': 'explore auth module'},
        ),
      );

      expect(result, isNotNull);
      expect(
        (result!.handle as SubagentFileHandle).path,
        '$_root/$childId/$childId.jsonl',
      );
      expect(
        result.messages
            .where((m) => m.role == AiRole.assistant)
            .first
            .parts
            .whereType<AiTextPart>()
            .single
            .text,
        'found routes',
      );
    },
  );

  test('multiple prompt matches pick nearest mtime to parent', () async {
    final fs = _MtimeFilesystem();
    const nearId = 'child-near';
    const farId = 'child-far';
    const prompt = 'scan dependencies';

    final reference = DateTime.utc(2026, 7, 28, 12, 0);
    await fs.writeString(
      _parentPath,
      _cursorTranscript(firstUserText: 'parent prompt'),
    );
    fs.setMtime(_parentPath, reference);

    final nearPath = '$_root/$nearId/$nearId.jsonl';
    final farPath = '$_root/$farId/$farId.jsonl';

    for (final entry in <(String path, Duration delta)>[
      (nearPath, const Duration(minutes: 1)),
      (farPath, const Duration(hours: 2)),
    ]) {
      await fs.writeString(
        entry.$1,
        _cursorTranscript(firstUserText: prompt, assistant: entry.$1),
      );
      fs.setMtime(entry.$1, reference.add(entry.$2));
    }

    final nearest = await _resolve(
      fs: fs,
      rootTranscriptPath: _parentPath,
      part: const AiToolCallPart(
        toolCallId: 'tool-near',
        toolName: 'Task',
        args: {'prompt': prompt},
      ),
    );
    expect(nearest, isNotNull);
    expect((nearest!.handle as SubagentFileHandle).path, nearPath);
  });

  test('equidistant prompt matches return null', () async {
    final fs = _MtimeFilesystem();
    const tieA = 'child-tie-a';
    const tieB = 'child-tie-b';
    const prompt = 'scan dependencies';

    final reference = DateTime.utc(2026, 7, 28, 12, 0);
    await fs.writeString(
      _parentPath,
      _cursorTranscript(firstUserText: 'parent prompt'),
    );
    fs.setMtime(_parentPath, reference);

    final tieAPath = '$_root/$tieA/$tieA.jsonl';
    final tieBPath = '$_root/$tieB/$tieB.jsonl';

    for (final path in [tieAPath, tieBPath]) {
      await fs.writeString(
        path,
        _cursorTranscript(firstUserText: prompt, assistant: path),
      );
      fs.setMtime(path, reference.add(const Duration(minutes: 5)));
    }

    final tied = await _resolve(
      fs: fs,
      rootTranscriptPath: _parentPath,
      part: const AiToolCallPart(
        toolCallId: 'tool-tie',
        toolName: 'Task',
        args: {'prompt': prompt},
      ),
    );
    expect(tied, isNull);
  });

  test('never reads Claude subagents layout even when present', () async {
    final fs = _SubagentsGuardFilesystem();
    const childId = 'child-sibling';
    final reference = DateTime.utc(2026, 7, 28, 12, 0);
    await fs.writeString(
      _parentPath,
      _cursorTranscript(firstUserText: 'parent'),
    );
    fs.setMtime(_parentPath, reference);
    await fs.writeString(
      '$_root/$_parentId/subagents/agent-only.jsonl',
      _cursorTranscript(firstUserText: 'only in subagents', assistant: 'bad'),
    );
    await fs.writeString(
      '$_root/$childId/$childId.jsonl',
      _cursorTranscript(firstUserText: 'sibling match', assistant: 'ok'),
    );
    fs.setMtime(
      '$_root/$childId/$childId.jsonl',
      reference.add(const Duration(minutes: 1)),
    );

    final result = await _resolve(
      fs: fs,
      rootTranscriptPath: _parentPath,
      part: const AiToolCallPart(
        toolCallId: 'tool-4',
        toolName: 'Task',
        args: {'prompt': 'sibling match'},
      ),
    );

    expect(result, isNotNull);
    expect(
      (result!.handle as SubagentFileHandle).path,
      '$_root/$childId/$childId.jsonl',
    );
    expect(fs.subagentsReadAttempts, 0);

    final miss = await _resolve(
      fs: fs,
      rootTranscriptPath: _parentPath,
      part: const AiToolCallPart(
        toolCallId: 'tool-5',
        toolName: 'Task',
        args: {'prompt': 'only in subagents'},
      ),
    );
    expect(miss, isNull);
    expect(fs.subagentsReadAttempts, 0);
  });

  test('missing resume UUID does not fall back to prompt heuristic', () async {
    final fs = _MtimeFilesystem();
    const childId = 'child-prompt-match';
    const prompt = 'would match if heuristic ran';
    final reference = DateTime.utc(2026, 7, 28, 12, 0);

    await fs.writeString(
      _parentPath,
      _cursorTranscript(firstUserText: 'parent'),
    );
    fs.setMtime(_parentPath, reference);
    await fs.writeString(
      '$_root/$childId/$childId.jsonl',
      _cursorTranscript(firstUserText: prompt, assistant: 'sibling'),
    );
    fs.setMtime(
      '$_root/$childId/$childId.jsonl',
      reference.add(const Duration(minutes: 1)),
    );

    expect(
      await _resolve(
        fs: fs,
        rootTranscriptPath: _parentPath,
        part: const AiToolCallPart(
          toolCallId: 'tool-resume-miss',
          toolName: 'Task',
          args: {'resume': 'missing-child-uuid', 'prompt': prompt},
        ),
      ),
      isNull,
    );
  });

  test('toolCallAt disambiguates prompt matches over parent mtime', () async {
    final fs = _MtimeFilesystem();
    const nearParentId = 'child-near-parent';
    const nearToolCallId = 'child-near-tool-call';
    const prompt = 'shared task prompt';

    final parentMtime = DateTime.utc(2026, 7, 28, 12, 0);
    final toolCallAt = parentMtime.add(const Duration(hours: 1, minutes: 50));

    await fs.writeString(
      _parentPath,
      _cursorTranscript(firstUserText: 'parent'),
    );
    fs.setMtime(_parentPath, parentMtime);

    final nearParentPath = '$_root/$nearParentId/$nearParentId.jsonl';
    final nearToolCallPath = '$_root/$nearToolCallId/$nearToolCallId.jsonl';

    await fs.writeString(
      nearParentPath,
      _cursorTranscript(firstUserText: prompt, assistant: 'near parent'),
    );
    fs.setMtime(nearParentPath, parentMtime.add(const Duration(minutes: 5)));

    await fs.writeString(
      nearToolCallPath,
      _cursorTranscript(firstUserText: prompt, assistant: 'near tool call'),
    );
    fs.setMtime(
      nearToolCallPath,
      parentMtime.add(const Duration(hours: 1, minutes: 55)),
    );

    final byParentClock = await _resolve(
      fs: fs,
      rootTranscriptPath: _parentPath,
      part: const AiToolCallPart(
        toolCallId: 'tool-clock-parent',
        toolName: 'Task',
        args: {'prompt': prompt},
      ),
    );
    expect(byParentClock, isNotNull);
    expect((byParentClock!.handle as SubagentFileHandle).path, nearParentPath);

    final byToolCallClock = await _resolve(
      fs: fs,
      rootTranscriptPath: _parentPath,
      toolCallAt: toolCallAt,
      part: const AiToolCallPart(
        toolCallId: 'tool-clock-call',
        toolName: 'Task',
        args: {'prompt': prompt},
      ),
    );
    expect(byToolCallClock, isNotNull);
    expect(
      (byToolCallClock!.handle as SubagentFileHandle).path,
      nearToolCallPath,
    );
  });

  test('miss returns null for unknown resume and unmatched prompt', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      _parentPath,
      _cursorTranscript(firstUserText: 'parent'),
    );
    await fs.writeString(
      '$_root/other/other.jsonl',
      _cursorTranscript(firstUserText: 'different prompt'),
    );

    expect(
      await _resolve(
        fs: fs,
        rootTranscriptPath: _parentPath,
        part: const AiToolCallPart(
          toolCallId: 'tool-miss-resume',
          toolName: 'Task',
          args: {'resume': 'missing-child'},
        ),
      ),
      isNull,
    );

    expect(
      await _resolve(
        fs: fs,
        rootTranscriptPath: _parentPath,
        part: const AiToolCallPart(
          toolCallId: 'tool-miss-prompt',
          toolName: 'Task',
          args: {'prompt': 'no sibling has this'},
        ),
      ),
      isNull,
    );
  });

  test(
    'flat parent layout resolves resume under same agent-transcripts root',
    () async {
      final fs = InMemoryFilesystem();
      const flatParent = '$_root/flat-parent.jsonl';
      const childId = 'flat-child';
      await fs.writeString(
        flatParent,
        _cursorTranscript(firstUserText: 'flat parent'),
      );
      await fs.writeString(
        '$_root/$childId/$childId.jsonl',
        _cursorTranscript(firstUserText: 'flat child', assistant: 'yes'),
      );

      final result = await _resolve(
        fs: fs,
        rootTranscriptPath: flatParent,
        part: const AiToolCallPart(
          toolCallId: 'tool-flat',
          toolName: 'agent',
          args: {'agentId': childId},
        ),
      );

      expect(result, isNotNull);
      expect(
        (result!.handle as SubagentFileHandle).path,
        '$_root/$childId/$childId.jsonl',
      );
    },
  );

  test('fingerprint lists sibling transcripts with size and mtime', () async {
    final fs = _MtimeFilesystem();
    await fs.writeString(_parentPath, _cursorTranscript(firstUserText: 'p'));
    const a = '$_root/child-a/child-a.jsonl';
    const b = '$_root/child-b/child-b.jsonl';
    await fs.writeString(a, 'aaa');
    await fs.writeString(b, 'bbbb');
    fs.setMtime(a, DateTime.utc(2026, 8, 1));
    fs.setMtime(b, DateTime.utc(2026, 8, 2));

    final token = await const CursorSideResolver().fingerprint(
      ctx: _ctx(fs),
      rootTranscriptPath: _parentPath,
    );
    expect(
      token,
      'child-a|3|2026-08-01T00:00:00.000Z\n'
      'child-b|4|2026-08-02T00:00:00.000Z',
    );
  });

  test('fingerprint ignores the parent stem and subagents dir', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(_parentPath, _cursorTranscript(firstUserText: 'p'));
    await fs.writeString('$_root/child-a/child-a.jsonl', 'x');
    await fs.writeString('$_root/subagents/agent-1.jsonl', 'y');

    final token = await const CursorSideResolver().fingerprint(
      ctx: _ctx(fs),
      rootTranscriptPath: _parentPath,
    );
    expect(token, contains('child-a'));
    expect(token, isNot(contains(_parentId)));
    expect(token, isNot(contains('subagents')));
  });

  test('fingerprint stats sibling transcripts concurrently', () async {
    final fs = _ConcurrentStatFilesystem();
    await fs.writeString(_parentPath, _cursorTranscript(firstUserText: 'p'));
    await fs.writeString('$_root/child-a/child-a.jsonl', 'aaa');
    await fs.writeString('$_root/child-b/child-b.jsonl', 'bbbb');

    final token = await const CursorSideResolver().fingerprint(
      ctx: _ctx(fs),
      rootTranscriptPath: _parentPath,
    );

    expect(token, contains('child-a'));
    expect(token, contains('child-b'));
    expect(fs.maxInFlight, greaterThanOrEqualTo(2));
  });
}

class _ConcurrentStatFilesystem extends InMemoryFilesystem {
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<FsStat> stat(String path) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    await Future<void>.delayed(Duration.zero);
    try {
      return await super.stat(path);
    } finally {
      _inFlight--;
    }
  }
}

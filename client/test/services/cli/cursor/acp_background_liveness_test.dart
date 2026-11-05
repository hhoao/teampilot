import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_background_liveness.dart';
import 'package:teampilot/services/cli/cursor/capabilities/acp_background_liveness.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../../support/in_memory_filesystem.dart';

const _toolDir = '/t/cursor';
const _sessionId = 'ses-1';
const _bucket = '/t/cursor/home/.cursor/projects/home-repo';
const _subagents = '$_bucket/agent-transcripts/$_sessionId/subagents';
const _terminals = '$_bucket/terminals';

/// [InMemoryFilesystem] plus the mtimes the liveness probe reads; the base
/// class reports files without one.
class _MtimeFilesystem extends InMemoryFilesystem {
  final Map<String, DateTime> mtimes = {};

  @override
  Future<FsStat> stat(String path) async {
    final base = await super.stat(path);
    final mtime = mtimes[path];
    if (mtime == null || !base.exists) return base;
    return FsStat(kind: base.kind, size: base.size, mtime: mtime);
  }
}

Future<_MtimeFilesystem> _filesystem({
  Map<String, String> children = const {},
  Map<String, String> terminals = const {},
}) async {
  final fs = _MtimeFilesystem();
  await fs.ensureDir('$_bucket/agent-transcripts/$_sessionId');
  for (final entry in children.entries) {
    await fs.ensureDir(_subagents);
    await fs.writeString('$_subagents/${entry.key}', entry.value);
  }
  for (final entry in terminals.entries) {
    await fs.ensureDir(_terminals);
    await fs.writeString('$_terminals/${entry.key}', entry.value);
  }
  return fs;
}

CursorBackgroundLivenessProbe _probe(
  _MtimeFilesystem fs, {
  DateTime Function()? now,
}) => CursorBackgroundLivenessProbe(
  fs: fs,
  sessionToolDir: _toolDir,
  sessionId: _sessionId,
  now: now,
);

String _runningChild() =>
    '{"type":"user","message":"hi"}\n'
    '{"type":"assistant","message":"working"}\n';

String _endedChild() =>
    '${_runningChild()}{"type":"turn_ended","status":"success"}\n';

String _terminal(String status) =>
    '---\n'
    'pid: 42\n'
    'command: "dart test"\n'
    'status: $status  \n'
    'running_for_ms: 1200   \n'
    '---\n'
    'output\n';

void main() {
  group('cursorSubagentTranscriptEnded', () {
    test('a turn_ended record closes the transcript', () {
      expect(cursorSubagentTranscriptEnded(_endedChild()), isTrue);
    });

    test('a child still writing is not closed', () {
      expect(cursorSubagentTranscriptEnded(_runningChild()), isFalse);
    });

    test('an empty or half-written file counts as running', () {
      expect(cursorSubagentTranscriptEnded(''), isFalse);
      expect(cursorSubagentTranscriptEnded('{"type":"turn'), isFalse);
    });
  });

  group('cursorTerminalStillRunning', () {
    final now = DateTime.utc(2026, 11, 3, 12);

    test('a fresh running terminal is live work', () {
      expect(
        cursorTerminalStillRunning(
          _terminal('running'),
          now: now,
          mtime: now.subtract(const Duration(seconds: 5)),
        ),
        isTrue,
      );
    });

    test('a finished terminal is not live work', () {
      for (final status in ['succeeded', 'failed', 'aborted']) {
        expect(
          cursorTerminalStillRunning(
            _terminal(status),
            now: now,
            mtime: now,
          ),
          isFalse,
          reason: status,
        );
      }
    });

    test('a running terminal whose file went cold is a crashed leftover', () {
      expect(
        cursorTerminalStillRunning(
          _terminal('running'),
          now: now,
          mtime: now.subtract(const Duration(minutes: 10)),
        ),
        isFalse,
      );
    });

    test('content without frontmatter is not live work', () {
      expect(cursorTerminalStillRunning('just output\n', now: now), isFalse);
    });
  });

  group('CursorBackgroundLivenessProbe', () {
    test('unknown when the session has no project bucket', () async {
      final fs = await _filesystem();
      await fs.removeRecursive(_bucket);
      expect(await _probe(fs).probe(), AcpBackgroundLiveness.unknown);
    });

    test('running while a child transcript is still open', () async {
      final fs = await _filesystem(
        children: {'a.jsonl': _runningChild()},
      );
      expect(await _probe(fs).probe(), AcpBackgroundLiveness.running);
    });

    test('idle once every child transcript has closed', () async {
      final fs = await _filesystem(
        children: {'a.jsonl': _endedChild(), 'b.jsonl': _endedChild()},
      );
      expect(await _probe(fs).probe(), AcpBackgroundLiveness.idle);
    });

    test('running while a background terminal is alive', () async {
      final fs = await _filesystem(terminals: {'400311.txt': _terminal('running')});
      expect(await _probe(fs).probe(), AcpBackgroundLiveness.running);
    });

    test('a finished terminal does not keep the lease', () async {
      final fs = await _filesystem(
        terminals: {'400311.txt': _terminal('succeeded')},
      );
      expect(await _probe(fs).probe(), AcpBackgroundLiveness.idle);
    });

    test('unknown when the only evidence predates the watch', () async {
      final fs = await _filesystem(children: {'a.jsonl': _endedChild()});
      final now = DateTime.utc(2026, 11, 3, 12);
      final armed = now.subtract(const Duration(minutes: 30));
      fs.mtimes['$_subagents/a.jsonl'] = now;
      final probe = _probe(fs, now: () => now);
      // Everything we can see finished long after the watch armed, but a
      // previous task's file must not clear a fresh lease: the caller passes
      // the arm time, and only evidence near it counts.
      expect(
        await probe.probe(since: armed.add(const Duration(seconds: 5))),
        AcpBackgroundLiveness.idle,
      );
      expect(
        await probe.probe(
          since: now.add(const Duration(minutes: 5)),
        ),
        AcpBackgroundLiveness.unknown,
      );
    });

    test('unknown when the session left no evidence at all', () async {
      final fs = await _filesystem();
      expect(await _probe(fs).probe(), AcpBackgroundLiveness.unknown);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/rewind/rewind_fork_service.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('rewind-fork-');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('rewind stops, restores, then relaunches', () async {
    final tmp = tmpDir.path;
    final store = await _personalStore(tmp);
    final first = await store.commitTurn(messageId: 'm1');
    await File('$tmp/work/claude/projects/a.jsonl').writeAsString('two');
    await store.commitTurn(messageId: 'm2');
    final seat = _FakeSeatProcess();

    await RewindForkService().rewind(
      store: store,
      seat: seat,
      commit: first.commit,
    );

    expect(
      await File('$tmp/work/claude/projects/a.jsonl').readAsString(),
      'one',
    );
    expect(seat.events, ['stopAndWait', 'relaunch']);
  });

  test('rewind refuses an in-flight turn', () async {
    final store = await _personalStore(tmpDir.path);
    final seat = _FakeSeatProcess(turnInFlight: true);

    await expectLater(
      RewindForkService().rewind(store: store, seat: seat, commit: 'unused'),
      throwsA(isA<StateError>()),
    );
    expect(seat.events, isEmpty);
  });

  test('rewind refuses a remote runtime', () async {
    final store = await _personalStore(tmpDir.path);
    final seat = _FakeSeatProcess(localRuntime: false);

    await expectLater(
      RewindForkService().rewind(store: store, seat: seat, commit: 'unused'),
      throwsA(isA<StateError>()),
    );
    expect(seat.events, isEmpty);
  });

  test('restore failure does not relaunch', () async {
    final store = await _personalStore(tmpDir.path);
    await store.commitTurn(messageId: 'm1');
    final seat = _FakeSeatProcess();

    await expectLater(
      RewindForkService().rewind(
        store: store,
        seat: seat,
        commit: 'not-a-commit',
      ),
      throwsA(isA<StateError>()),
    );
    expect(seat.events, ['stopAndWait']);
  });

  test(
    'fork does not stop the source and deletes the session on failure',
    () async {
      final tmp = tmpDir.path;
      final source = await _personalStore(tmp);
      final first = await source.commitTurn(
        messageId: 'm1',
        nativeSessionId: 'sid-1',
      );
      await File('$tmp/work/claude/projects/a.jsonl').writeAsString('two');
      await source.commitTurn(messageId: 'm2', nativeSessionId: 'sid-2');
      await File('$tmp/dest.git').writeAsString('not a git directory');
      final seat = _FakeSeatProcess();
      final sessions = _FakeForkSessionCreator(id: 'created-1');

      await expectLater(
        RewindForkService().fork(
          source: source,
          commit: first.commit,
          destTarget: const SeatRewindTarget(
            kind: SeatRewindKind.personalAcp,
            tool: 'claude',
          ),
          destGitDir: '$tmp/dest.git',
          destWorkTree: '$tmp/dest-work',
          sessions: sessions,
          workspaceId: 'ws',
          cli: CliTool.claude,
          display: 'claude fork',
          workingDirectory: '/proj',
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(seat.events, isEmpty);
      expect(sessions.deleted, ['created-1']);
      expect(sessions.nativeSessionId, 'sid-1');
      expect(
        await File('$tmp/work/claude/projects/a.jsonl').readAsString(),
        'two',
      );
    },
  );
}

Future<SeatRewindStore> _personalStore(String tmp) async {
  await Directory('$tmp/work/claude/projects').create(recursive: true);
  await File('$tmp/work/claude/projects/a.jsonl').writeAsString('one');
  await File('$tmp/work/acp-transcript.jsonl').writeAsString('[]');
  await File('$tmp/work/acp-session.json').writeAsString('{"v":1}');
  return SeatRewindStore(
    gitDir: '$tmp/repo.git',
    workTree: '$tmp/work',
    target: const SeatRewindTarget(
      kind: SeatRewindKind.personalAcp,
      tool: 'claude',
    ),
  );
}

final class _FakeSeatProcess implements SeatProcess {
  _FakeSeatProcess({this.turnInFlight = false, this.localRuntime = true});

  @override
  final bool turnInFlight;

  @override
  final bool localRuntime;

  final events = <String>[];

  @override
  Future<void> stopAndWait() async {
    events.add('stopAndWait');
  }

  @override
  Future<void> relaunch() async {
    events.add('relaunch');
  }
}

final class _FakeForkSessionCreator implements ForkSessionCreator {
  _FakeForkSessionCreator({required this.id});

  final String id;
  final deleted = <String>[];
  String? nativeSessionId;

  @override
  Future<String> createPersonal({
    required String workspaceId,
    required CliTool cli,
    required String display,
    required String? workingDirectory,
    required String? nativeSessionId,
  }) async {
    this.nativeSessionId = nativeSessionId;
    return id;
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    deleted.add(sessionId);
  }
}

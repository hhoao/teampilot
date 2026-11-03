import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';
import 'package:teampilot/services/chat/conversation/history/later_checkpoint_messages.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_history_capability.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('later-checkpoint-');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test(
    'paged-window-missing ancestor ids are not ghosts; later keeps are',
    () async {
      final store = await _personalAcpStore(tmpDir.path);
      final m1 = _user('m1', 'one');
      final mZ2 = _user('m_z2', 'later first');
      final mA2 = _user('m_a2', 'later second');

      await _writeTranscript(store, [m1]);
      final first = await store.commitTurn(messageId: m1.id);
      await _writeTranscript(store, [m1, mZ2]);
      final second = await store.commitTurn(messageId: mZ2.id);
      await _writeTranscript(store, [m1, mZ2, mA2]);
      await store.commitTurn(messageId: mA2.id);
      await store.restore(first.commit);

      // Paged window is missing m1 (it is on the checked-out commit).
      final history = await readSeatRewindHistory(store: store, acp: true);

      expect(history.checkedOutCommit, first.commit);
      expect(history.laterMessages.map((m) => m.id).toList(), [mZ2.id, mA2.id]);
      expect(history.checkpointCommits[mZ2.id], second.commit);
      expect(
        history.laterMessages,
        isNot(contains(predicate<AiMessage>((m) => m.id == m1.id))),
      );
    },
  );

  test(
    'showFile on opencode.db does not clear checkpoint commits',
    () async {
      final tmp = tmpDir.path;
      await Directory('$tmp/work/opencode').create(recursive: true);
      await File('$tmp/work/opencode/opencode.db').writeAsBytes([
        ... 'SQLite format 3'.codeUnits,
        0x00,
        0xFF,
        0xFE,
        0x80,
      ]);
      final store = SeatRewindStore(
        gitDir: '$tmp/repo.git',
        workTree: '$tmp/work',
        target: const SeatRewindTarget(
          kind: SeatRewindKind.personalPty,
          tool: 'opencode',
        ),
      );
      final checkpoint = await store.commitTurn(messageId: 'm1');

      Object? error;
      SeatRewindHistory? history;
      try {
        history = await readSeatRewindHistory(
          store: store,
          acp: false,
          history: const OpencodeAiHistoryCapability(),
          ptyRelativePath: 'opencode/opencode.db',
        );
      } on Object catch (caught) {
        error = caught;
      }

      expect(error, isNull);
      expect(history?.checkpointCommits['m1'], checkpoint.commit);
      expect(history?.laterMessages, isEmpty);
    },
  );
}

Future<SeatRewindStore> _personalAcpStore(String tmp) async {
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

AiMessage _user(String id, String text) => AiMessage(
  id: id,
  role: AiRole.user,
  parts: [AiTextPart(text: text)],
);

Future<void> _writeTranscript(
  SeatRewindStore store,
  List<AiMessage> messages,
) async {
  await File(
    '${store.workTree}/acp-transcript.jsonl',
  ).writeAsString(encodeAcpChatTranscript(messages));
}

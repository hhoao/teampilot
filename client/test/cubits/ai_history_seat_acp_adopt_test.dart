import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';
import 'package:teampilot/services/chat/conversation/history/ai_history_loader.dart';
import 'package:teampilot/services/chat/conversation/history/session_history_pagination.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

class _EmptyAdapter implements AiTranscriptAdapter {
  const _EmptyAdapter();

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}

void main() {
  late AiHistorySeat seat;

  List<AiMessage> nMessages(int count) => [
    for (var i = 0; i < count; i++)
      AiMessage(
        id: 'm-$i',
        role: AiRole.user,
        parts: [AiTextPart(text: 'msg-$i')],
      ),
  ];

  setUp(() {
    setUpTestAppStorage();
    final fs = LocalFilesystem();
    seat = AiHistorySeat(
      loader: AiHistoryLoader(
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: fs,
          home: '/tmp/acp-adopt',
          cwd: '/tmp/acp-adopt',
          appDataRoot: '/tmp/acp-adopt',
          paths: AppPaths('/tmp/acp-adopt'),
        ),
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: const _EmptyAdapter(),
        ),
      ),
    );
  });

  tearDown(() async {
    await seat.close();
    tearDownTestAppStorage();
  });

  test('first adopt after loading windows to the latest 30 turns', () {
    seat.markExternalLoading();
    seat.adoptExternalMessages(nMessages(35));
    expect(seat.state.status, AiHistoryViewStatus.ready);
    expect(seat.loadedMessages, hasLength(35));
    expect(seat.runtime.messages, hasLength(kSessionHistoryInitialTurns));
    expect(seat.runtime.messages.first.id, 'm-5');
    expect(seat.runtime.messages.last.id, 'm-34');
    expect(seat.state.hasOlder, isTrue);
    expect(seat.state.totalMessageCount, 35);
  });

  test('loadOlder expands the in-memory ACP window', () async {
    seat.markExternalLoading();
    seat.adoptExternalMessages(nMessages(35));
    await seat.loadOlder();
    expect(seat.runtime.messages, hasLength(35));
    expect(seat.state.hasOlder, isFalse);
  });

  test('live adopt grows the tail without resetting the window to 30', () {
    seat.markExternalLoading();
    seat.adoptExternalMessages(nMessages(35));
    expect(seat.runtime.messages, hasLength(30));
    seat.adoptExternalMessages([
      ...nMessages(35),
      AiMessage(
        id: 'm-35',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'msg-35')],
      ),
    ]);
    expect(seat.loadedMessages, hasLength(36));
    expect(seat.runtime.messages, hasLength(31));
    expect(seat.runtime.messages.last.id, 'm-35');
  });

  test(
    'adopt drops leftover pending so the cubit user is not painted twice',
    () {
      seat.enqueuePendingUser('hello from landing');
      expect(seat.runtime.messages, hasLength(1));
      expect(seat.runtime.messages.single.id, startsWith('pending:'));

      seat.adoptExternalMessages([
        AiMessage(
          id: 'acp-u-1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'hello from landing')],
        ),
      ]);

      expect(seat.runtime.messages, hasLength(1));
      expect(seat.runtime.messages.single.id, 'acp-u-1');
    },
  );

  test(
    'live adopt with the same length keeps the window and updates the tip',
    () {
      seat.markExternalLoading();
      final first = [
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'hi')],
        ),
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'Hel')],
        ),
      ];
      seat.adoptExternalMessages(first);
      seat.setAwaitingAssistant(true);
      seat.adoptExternalMessages([
        first[0],
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: const [AiTextPart(text: 'Hello')],
        ),
      ]);
      expect(seat.runtime.messages, hasLength(2));
      expect(
        (seat.runtime.messages.last.parts.single as AiTextPart).text,
        'Hello',
      );
    },
  );

  test('mergeExternalMessages replaces by id and appends new ids', () {
    seat.markExternalLoading();
    seat.adoptExternalMessages(nMessages(3));

    seat.mergeExternalMessages([
      const AiMessage(
        id: 'm-1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'changed')],
      ),
      const AiMessage(
        id: 'm-3',
        role: AiRole.user,
        parts: [AiTextPart(text: 'new')],
      ),
    ]);

    final byId = {
      for (final message in seat.loadedMessages) message.id: message,
    };
    expect((byId['m-1']!.parts.single as AiTextPart).text, 'changed');
    expect((byId['m-3']!.parts.single as AiTextPart).text, 'new');
    expect(seat.loadedMessages, hasLength(4));
  });

  test('applyExternalTranscriptDelta updates and drops by record id', () {
    seat.markExternalLoading();
    final user = const AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
    );
    final gone = const AiMessage(
      id: 'a-old',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'old')],
    );
    seat.adoptExternalMessages([user, gone]);

    final assistant = const AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'Hello')],
    );
    final records = buildAcpChatTranscriptDelta(
      previous: [user, gone],
      next: [user, assistant],
    );
    seat.applyExternalTranscriptDelta(records!.map(jsonEncode).join('\n'));

    final byId = {
      for (final message in seat.loadedMessages) message.id: message,
    };
    expect(byId.containsKey('a-old'), isFalse);
    expect((byId['a1']!.parts.single as AiTextPart).text, 'Hello');
  });
}

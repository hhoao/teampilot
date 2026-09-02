import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late _RecordingChatCubit cubit;

  setUp(() {
    setUpTestAppStorage();
    cubit = _RecordingChatCubit()..registerPersonalSession();
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test(
    'PTY follow-up persists pending before deliver and stales History',
    () async {
      final stale = <String>[];
      cubit.onSessionHistoryStale = stale.add;
      cubit.peekChannel = HistoryContinueChannel.pty;
      cubit.deliveryChannel = HistoryContinueChannel.pty;
      cubit.enqueueFollowUp('follow up');

      await cubit.resumeFollowUpQueue('session-1', 'selected-member');

      expect(cubit.calls, [
        'persist:workspace-1:session-1:session-1:follow up',
        'deliver:session-1:session-1:follow up',
      ]);
      expect(stale, ['session-1']);
    },
  );

  test(
    'mailbox follow-up emits once and does not persist History pending',
    () async {
      cubit.peekChannel = HistoryContinueChannel.mailbox;
      cubit.deliveryChannel = HistoryContinueChannel.mailbox;
      cubit.enqueueFollowUp('mail follow up');
      final queued = cubit.operatorMailboxQueued.first;

      await cubit.resumeFollowUpQueue('session-1', 'selected-member');
      final event = await queued;

      expect(cubit.persistCount, 0);
      expect(cubit.calls, ['deliver:session-1:session-1:mail follow up']);
      expect(event.sessionId, 'session-1');
      expect(event.memberId, 'session-1');
      expect(event.mailId, 'mail-1');
      expect(event.text, 'mail follow up');
    },
  );

  test(
    'follow-up uses mailbox result UX when initial channel peek was PTY',
    () async {
      final stale = <String>[];
      cubit.onSessionHistoryStale = stale.add;
      cubit.peekChannel = HistoryContinueChannel.pty;
      cubit.deliveryChannel = HistoryContinueChannel.mailbox;
      cubit.enqueueFollowUp('channel flipped');
      final queued = cubit.operatorMailboxQueued.first;

      await cubit.resumeFollowUpQueue('session-1', 'selected-member');
      final event = await queued;

      expect(cubit.calls, [
        'persist:workspace-1:session-1:session-1:channel flipped',
        'deliver:session-1:session-1:channel flipped',
        'clear:workspace-1:session-1:session-1:pending-1',
      ]);
      expect(stale, isEmpty);
      expect(event.mailId, 'mail-1');
    },
  );
}

final class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  HistoryContinueChannel peekChannel = HistoryContinueChannel.pty;
  HistoryContinueChannel deliveryChannel = HistoryContinueChannel.pty;
  final calls = <String>[];
  var persistCount = 0;

  void registerPersonalSession() {
    tabStore.registerSession(
      ChatTab(
          info: const ChatTabInfo(
            id: 'session-1',
            title: 'Session',
            subtitle: '',
          ),
          cliTeamName: '',
          workspaceId: 'workspace-1',
        )
        ..persistedSession = AppSession(
          sessionId: 'session-1',
          workspaceId: 'workspace-1',
          sessionTeam: '',
          cli: CliTool.claude,
          createdAt: 0,
        ),
    );
  }

  void enqueueFollowUp(String text) {
    followUpQueue.enqueue(
      followUpSeatKey('session-1', 'selected-member'),
      text,
    );
  }

  @override
  HistoryContinueChannel resolveOperatorMessageChannel(
    String sessionId,
    String shellMemberId,
  ) => peekChannel;

  @override
  Future<FailedMessageRecord?> persistHistoryPending({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    required String text,
  }) async {
    persistCount += 1;
    calls.add('persist:$workspaceId:$sessionId:$memberId:$text');
    return FailedMessageRecord(
      id: 'pending-1',
      text: text,
      createdAt: DateTime.utc(2026),
      status: FailedMessageStatus.sending,
    );
  }

  @override
  Future<void> clearHistoryPending({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    required String recordId,
  }) async {
    calls.add('clear:$workspaceId:$sessionId:$memberId:$recordId');
  }

  @override
  Future<HistoryContinueSubmitResult> submitSessionOperatorMessage({
    required String sessionId,
    required String memberId,
    required String message,
    bool preserveWorkbenchView = true,
  }) async {
    calls.add('deliver:$sessionId:$memberId:$message');
    return HistoryContinueSubmitResult(
      ok: true,
      channel: deliveryChannel,
      mailId: deliveryChannel == HistoryContinueChannel.mailbox
          ? 'mail-1'
          : null,
    );
  }
}

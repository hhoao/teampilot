import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/session_history_review_submit.dart';

void main() {
  group('submitSessionHistoryReviewMessage', () {
    late ExistingSessionConnect connectRequest;
    late List<SessionConnectRequest> connectCalls;
    late List<(String, String, bool)> readyCalls;
    late List<(String, String, String, bool)> deliverCalls;
    late List<(String, String)> titleCalls;
    late int openSessionCalls;

    setUp(() {
      connectRequest = ExistingSessionConnect(
        session: AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws-1',
          folders: const [WorkspaceFolder(path: '/tmp')],
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      connectCalls = [];
      readyCalls = [];
      deliverCalls = [];
      titleCalls = [];
      openSessionCalls = 0;
    });

    Future<HistoryContinueSubmitResult> runSubmit(
      String message, {
      HistoryContinueChannel channel = HistoryContinueChannel.pty,
      String? mailboxMailId = 'mail-1',
    }) {
      return submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: message,
        channel: channel,
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
        },
        ensureMemberInputReady:
            (sessionId, memberId, {bool directToPty = false}) async {
              readyCalls.add((sessionId, memberId, directToPty));
            },
        deliverUserCommandToMember:
            (sessionId, memberId, text, {bool directToPty = false}) async {
              deliverCalls.add((sessionId, memberId, text, directToPty));
              return directToPty ? null : mailboxMailId;
            },
        applyFirstPromptTitle: (sessionId, firstPrompt) async {
          titleCalls.add((sessionId, firstPrompt));
        },
      );
    }

    test('empty or whitespace message is a no-op', () async {
      expect((await runSubmit('')).ok, isFalse);
      expect((await runSubmit('   ')).ok, isFalse);
      expect(connectCalls, isEmpty);
      expect(deliverCalls, isEmpty);
      expect(openSessionCalls, 0);
    });

    test(
      'pty: connects, waits for member, delivers, and titles — '
      'without requestOpenSession',
      () async {
        final result = await runSubmit('  continue here  ');

        expect(result.ok, isTrue);
        expect(result.channel, HistoryContinueChannel.pty);
        expect(result.mailId, isNull);
        expect(connectCalls, [connectRequest]);
        expect(readyCalls, [('sess-1', 'member-1', true)]);
        expect(deliverCalls, [('sess-1', 'member-1', 'continue here', true)]);
        expect(titleCalls, [('sess-1', 'continue here')]);
        expect(openSessionCalls, 0);
      },
    );

    test(
      'mailbox: connects and delivers without ready-wait or PTY inject',
      () async {
        final result = await runSubmit(
          '  follow up  ',
          channel: HistoryContinueChannel.mailbox,
        );

        expect(result.ok, isTrue);
        expect(result.channel, HistoryContinueChannel.mailbox);
        expect(result.mailId, 'mail-1');
        expect(connectCalls, [connectRequest]);
        expect(readyCalls, isEmpty);
        expect(deliverCalls, [('sess-1', 'member-1', 'follow up', false)]);
        expect(titleCalls, isEmpty);
      },
    );

    test('mailbox fails when deliver returns empty mail id', () async {
      final result = await runSubmit(
        'hello',
        channel: HistoryContinueChannel.mailbox,
        mailboxMailId: '',
      );

      expect(result.ok, isFalse);
      expect(deliverCalls, [('sess-1', 'member-1', 'hello', false)]);
      expect(titleCalls, isEmpty);
    });

    test(
      'resolveChannel after connect can switch pty default to mailbox',
      () async {
        var connected = false;
        final result = await submitSessionHistoryReviewMessage(
          sessionId: 'sess-1',
          memberId: 'member-1',
          message: 'hello',
          channel: HistoryContinueChannel.pty,
          resolveChannel: () => connected
              ? HistoryContinueChannel.mailbox
              : HistoryContinueChannel.pty,
          connectRequest: connectRequest,
          connectWorkspaceSession: (request) async {
            connectCalls.add(request);
            connected = true;
          },
          ensureMemberInputReady:
              (sessionId, memberId, {bool directToPty = false}) async {
                readyCalls.add((sessionId, memberId, directToPty));
              },
          deliverUserCommandToMember:
              (sessionId, memberId, text, {bool directToPty = false}) async {
                deliverCalls.add((sessionId, memberId, text, directToPty));
                return 'mail-post';
              },
          applyFirstPromptTitle: (sessionId, firstPrompt) async {
            titleCalls.add((sessionId, firstPrompt));
          },
        );

        expect(result.ok, isTrue);
        expect(result.channel, HistoryContinueChannel.mailbox);
        expect(result.mailId, 'mail-post');
        expect(readyCalls, isEmpty);
        expect(deliverCalls, [('sess-1', 'member-1', 'hello', false)]);
        expect(titleCalls, isEmpty);
      },
    );

    test('keeps failure when connect throws', () async {
      final result = await submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: 'hello',
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
          throw StateError('connect failed');
        },
        ensureMemberInputReady:
            (sessionId, memberId, {bool directToPty = false}) async {
              readyCalls.add((sessionId, memberId, directToPty));
            },
        deliverUserCommandToMember:
            (sessionId, memberId, text, {bool directToPty = false}) async {
              deliverCalls.add((sessionId, memberId, text, directToPty));
              return null;
            },
        applyFirstPromptTitle: (sessionId, firstPrompt) async {
          titleCalls.add((sessionId, firstPrompt));
        },
      );

      expect(result.ok, isFalse);
      expect(connectCalls, [connectRequest]);
      expect(readyCalls, isEmpty);
      expect(deliverCalls, isEmpty);
    });

    test('keeps failure when member never becomes ready', () async {
      final result = await submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: 'hello',
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
        },
        ensureMemberInputReady:
            (sessionId, memberId, {bool directToPty = false}) async {
              readyCalls.add((sessionId, memberId, directToPty));
              throw TimeoutException('not ready');
            },
        deliverUserCommandToMember:
            (sessionId, memberId, text, {bool directToPty = false}) async {
              deliverCalls.add((sessionId, memberId, text, directToPty));
              return null;
            },
        applyFirstPromptTitle: (sessionId, firstPrompt) async {
          titleCalls.add((sessionId, firstPrompt));
        },
        readyTimeout: const Duration(milliseconds: 1),
      );

      expect(result.ok, isFalse);
      expect(connectCalls, [connectRequest]);
      expect(deliverCalls, isEmpty);
      expect(titleCalls, isEmpty);
    });

    test('keeps failure when deliver throws', () async {
      final result = await submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: 'hello',
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
        },
        ensureMemberInputReady:
            (sessionId, memberId, {bool directToPty = false}) async {
              readyCalls.add((sessionId, memberId, directToPty));
            },
        deliverUserCommandToMember:
            (sessionId, memberId, text, {bool directToPty = false}) async {
              deliverCalls.add((sessionId, memberId, text, directToPty));
              throw StateError('inject failed');
            },
        applyFirstPromptTitle: (sessionId, firstPrompt) async {
          titleCalls.add((sessionId, firstPrompt));
        },
      );

      expect(result.ok, isFalse);
      expect(deliverCalls, [('sess-1', 'member-1', 'hello', true)]);
      expect(titleCalls, isEmpty);
    });
  });
}

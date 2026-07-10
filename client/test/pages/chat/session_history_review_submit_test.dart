import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
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

    Future<bool> runSubmit(String message) {
      return submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: message,
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
        },
        ensureMemberInputReady: (sessionId, memberId, {bool directToPty = false}) async {
          readyCalls.add((sessionId, memberId, directToPty));
        },
        deliverUserCommandToMember:
            (sessionId, memberId, text, {bool directToPty = false}) async {
              deliverCalls.add((sessionId, memberId, text, directToPty));
            },
        applyFirstPromptTitle: (sessionId, firstPrompt) async {
          titleCalls.add((sessionId, firstPrompt));
        },
      );
    }

    test('empty or whitespace message is a no-op', () async {
      expect(await runSubmit(''), isFalse);
      expect(await runSubmit('   '), isFalse);
      expect(connectCalls, isEmpty);
      expect(deliverCalls, isEmpty);
      expect(openSessionCalls, 0);
    });

    test(
      'connects open tab, waits for member, delivers, and titles — '
      'without requestOpenSession',
      () async {
        final ok = await runSubmit('  continue here  ');

        expect(ok, isTrue);
        expect(connectCalls, [connectRequest]);
        expect(readyCalls, [('sess-1', 'member-1', true)]);
        expect(deliverCalls, [('sess-1', 'member-1', 'continue here', true)]);
        expect(titleCalls, [('sess-1', 'continue here')]);
        expect(openSessionCalls, 0);
      },
    );

    test('keeps failure when connect throws', () async {
      final ok = await submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: 'hello',
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
          throw StateError('connect failed');
        },
        ensureMemberInputReady: (sessionId, memberId, {bool directToPty = false}) async {
          readyCalls.add((sessionId, memberId, directToPty));
        },
        deliverUserCommandToMember:
            (sessionId, memberId, text, {bool directToPty = false}) async {
              deliverCalls.add((sessionId, memberId, text, directToPty));
            },
        applyFirstPromptTitle: (sessionId, firstPrompt) async {
          titleCalls.add((sessionId, firstPrompt));
        },
      );

      expect(ok, isFalse);
      expect(connectCalls, [connectRequest]);
      expect(readyCalls, isEmpty);
      expect(deliverCalls, isEmpty);
    });

    test('keeps failure when member never becomes ready', () async {
      final ok = await submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: 'hello',
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
        },
        ensureMemberInputReady: (sessionId, memberId, {bool directToPty = false}) async {
          readyCalls.add((sessionId, memberId, directToPty));
          throw TimeoutException('not ready');
        },
        deliverUserCommandToMember:
            (sessionId, memberId, text, {bool directToPty = false}) async {
              deliverCalls.add((sessionId, memberId, text, directToPty));
            },
        applyFirstPromptTitle: (sessionId, firstPrompt) async {
          titleCalls.add((sessionId, firstPrompt));
        },
        readyTimeout: const Duration(milliseconds: 1),
      );

      expect(ok, isFalse);
      expect(connectCalls, [connectRequest]);
      expect(deliverCalls, isEmpty);
      expect(titleCalls, isEmpty);
    });

    test('keeps failure when deliver throws', () async {
      final ok = await submitSessionHistoryReviewMessage(
        sessionId: 'sess-1',
        memberId: 'member-1',
        message: 'hello',
        connectRequest: connectRequest,
        connectWorkspaceSession: (request) async {
          connectCalls.add(request);
        },
        ensureMemberInputReady: (sessionId, memberId, {bool directToPty = false}) async {
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

      expect(ok, isFalse);
      expect(deliverCalls, [('sess-1', 'member-1', 'hello', true)]);
      expect(titleCalls, isEmpty);
    });
  });
}

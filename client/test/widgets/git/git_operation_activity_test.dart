import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:teampilot/widgets/git/git_operation_activity.dart';

import '../../support/post_frame_test_harness.dart';

class _FakeRecorder implements NotificationRecorder {
  final List<(String, TpToastVariant)> records = [];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {
    records.add((message, variant));
  }
}

void main() {
  late ProgressActivityCubit progress;
  late _FakeRecorder recorder;

  setUp(() {
    setUpTestAppStorage();
    recorder = _FakeRecorder();
    NotificationRecorder.install(recorder);
    progress = ProgressActivityCubit(historyRecorder: recorder);
  });

  tearDown(() async {
    NotificationRecorder.install(null);
    AppToast.dismiss();
    await progress.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpRunner(
    WidgetTester tester, {
    required Future<bool> Function() body,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<ProgressActivityCubit>.value(
          value: progress,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  runGitOperation(
                    context,
                    workspaceId: 'ws-1',
                    repoRoot: '/repo',
                    title: '正在推送…',
                    doneMessage: '推送完成',
                    body: body,
                  ),
                ),
                child: const Text('run'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a workspace-scoped activity while running', (
    tester,
  ) async {
    final gate = Completer<bool>();
    await pumpRunner(tester, body: () => gate.future);

    await tester.tap(find.text('run'));
    await tester.pump();

    final activities = progress.state.activities;
    expect(activities, hasLength(1));
    expect(activities.single.kind, ProgressActivityKind.gitOperation);
    expect(activities.single.title, '正在推送…');
    expect(activities.single.workspaceId, 'ws-1');
    expect(activities.single.subtitle, 'repo');

    gate.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(progress.state.activities, isEmpty);

    AppToast.dismiss();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a success records exactly one history entry (the toast)', (
    tester,
  ) async {
    await pumpRunner(tester, body: () async => true);

    await tester.tap(find.text('run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('推送完成'), findsOneWidget);
    expect(recorder.records, hasLength(1));
    expect(recorder.records.single.$2, TpToastVariant.success);

    AppToast.dismiss();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a failure shows no success toast', (tester) async {
    await pumpRunner(tester, body: () async => false);

    await tester.tap(find.text('run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('推送完成'), findsNothing);
    expect(recorder.records, isEmpty);
    expect(progress.state.activities, isEmpty);
  });
}

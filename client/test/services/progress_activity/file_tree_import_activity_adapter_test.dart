import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/progress_activity/file_tree_import_activity_adapter.dart';

class _FakeNotificationRecorder implements NotificationRecorder {
  final records = <({String message, TpToastVariant variant, String title})>[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {
    records.add((message: message, variant: variant, title: title));
  }
}

ImportPlan _smallLocalPlan() {
  return ImportPlan(
    sources: const [ImportSource(path: '/src/a.txt', isDirectory: false)],
    destDir: '/dest',
    mode: ImportMode.copy,
    sourceFs: LocalFilesystem(),
    destFs: LocalFilesystem(),
    flattenedFileCount: 1,
    maxFileBytes: 100,
    destIsLocal: true,
  );
}

ImportPlan _largeLocalPlan() {
  return ImportPlan(
    sources: const [ImportSource(path: '/src', isDirectory: true)],
    destDir: '/dest',
    mode: ImportMode.copy,
    sourceFs: LocalFilesystem(),
    destFs: LocalFilesystem(),
    flattenedFileCount: 20,
    maxFileBytes: 100,
    destIsLocal: true,
  );
}

void main() {
  group('FileTreeImportActivityAdapter', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit cubit;
    late WorkspaceImportService importService;
    late FileTreeImportActivityAdapter adapter;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      cubit = ProgressActivityCubit(historyRecorder: recorder);
      importService = WorkspaceImportService();
      adapter = FileTreeImportActivityAdapter(
        cubit: cubit,
        importService: importService,
      );
    });

    tearDown(() {
      importService.dispose();
      cubit.close();
    });

    test('skips activity tracking below progress gate', () async {
      var cancelChecked = false;

      final summary = await adapter.runTracked(
        plan: _smallLocalPlan(),
        title: 'Importing',
        workspaceId: 'ws-1',
        historyMessageFor: (_) => 'done',
        runImport: ({required isCancelled}) async {
          cancelChecked = isCancelled();
          return const ImportSummary(succeeded: 1);
        },
      );

      expect(summary.succeeded, 1);
      expect(cancelChecked, isFalse);
      expect(cubit.state.activities, isEmpty);
      expect(recorder.records, isEmpty);
    });

    test('tracks progress and completes succeeded', () async {
      String? startedId;
      final progressController = StreamController<ImportProgress>.broadcast();
      addTearDown(progressController.close);

      final summary = await adapter.runTracked(
        plan: _largeLocalPlan(),
        title: 'Importing',
        workspaceId: 'ws-1',
        historyMessageFor: (_) => '2 succeeded, 0 skipped, 0 failed',
        onActivityStarted: (id) => startedId = id,
        progressStreamOverride: progressController.stream,
        runImport: ({required isCancelled}) async {
          progressController.add(
            const ImportProgress(
              completedItems: 1,
              totalItems: 2,
              currentName: 'one.txt',
              bytesDone: 50,
              bytesTotal: 100,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          return const ImportSummary(succeeded: 2);
        },
      );

      expect(summary.succeeded, 2);
      expect(startedId, isNotNull);
      expect(cubit.state.activities, isEmpty);
      expect(recorder.records, hasLength(1));
      expect(recorder.records.first.variant, TpToastVariant.success);
      expect(recorder.records.first.message, '2 succeeded, 0 skipped, 0 failed');
    });

    test('cancel hook sets isCancelled for runImport', () async {
      var cancelled = false;

      await adapter.runTracked(
        plan: _largeLocalPlan(),
        title: 'Importing',
        historyMessageFor: (_) => 'cancelled',
        runImport: ({required isCancelled}) async {
          final activityId = cubit.state.activities.single.id;
          cubit.requestCancel(activityId);
          await Future<void>.delayed(Duration.zero);
          cancelled = isCancelled();
          return const ImportSummary(succeeded: 1, cancelled: true);
        },
      );

      expect(cancelled, isTrue);
      expect(recorder.records.single.variant, TpToastVariant.warning);
    });

    test('failed summary completes with failed outcome', () async {
      await adapter.runTracked(
        plan: _largeLocalPlan(),
        title: 'Importing',
        historyMessageFor: (_) => '1 succeeded, 0 skipped, 2 failed',
        runImport: ({required isCancelled}) async {
          return const ImportSummary(succeeded: 1, failed: 2);
        },
      );

      expect(recorder.records.single.variant, TpToastVariant.error);
    });

    test('updates cubit from import progress stream', () async {
      final progressController = StreamController<ImportProgress>.broadcast();
      final runGate = Completer<void>();
      addTearDown(progressController.close);

      final runFuture = adapter.runTracked(
        plan: _largeLocalPlan(),
        title: 'Importing',
        historyMessageFor: (_) => 'done',
        progressStreamOverride: progressController.stream,
        runImport: ({required isCancelled}) async {
          progressController.add(
            const ImportProgress(
              completedItems: 1,
              totalItems: 3,
              currentName: 'foo.txt',
            ),
          );
          await runGate.future;
          return const ImportSummary(succeeded: 3);
        },
      );

      await Future<void>.delayed(Duration.zero);
      final activity = cubit.state.activities.single;
      expect(activity.kind, ProgressActivityKind.fileTreeImport);
      expect(activity.subtitle, 'foo.txt');
      expect(activity.completedItems, 1);
      expect(activity.totalItems, 3);
      expect(activity.cancellable, isTrue);

      runGate.complete();
      await runFuture;
    });
  });
}

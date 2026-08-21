import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_cancelled_exception.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/services/install/install_job_keys.dart';
import 'package:teampilot/services/install/runners/file_tree_import_install_job_runner.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

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
  group('FileTreeImportInstallJobRunner', () {
    late WorkspaceImportService importService;
    late FileTreeImportInstallJobRunner runner;

    setUp(() {
      importService = WorkspaceImportService();
      runner = FileTreeImportInstallJobRunner(importService: importService);
    });

    tearDown(() {
      importService.dispose();
    });

    test('supports fileTreeImport keys', () {
      expect(
        runner.supports(InstallJobKeys.fileImport('ws-1', 'hash')),
        isTrue,
      );
      expect(
        runner.supports(InstallJobKeys.skill('lint')),
        isFalse,
      );
    });

    test('execute skips progress tracking below gate', () async {
      var cancelChecked = false;

      final summary = await runner.execute(
        plan: _smallLocalPlan(),
        ctx: InstallJobContext(),
        runImport: ({required isCancelled}) async {
          cancelChecked = isCancelled();
          return const ImportSummary(succeeded: 1);
        },
      );

      expect(summary.succeeded, 1);
      expect(cancelChecked, isFalse);
    });

    test('execute tracks progress and wires isCancelled from ctx', () async {
      final progressController = StreamController<ImportProgress>.broadcast();
      addTearDown(progressController.close);
      final reported = <String>[];

      final summary = await runner.execute(
        plan: _largeLocalPlan(),
        ctx: InstallJobContext(
          reportPhase: (label, {detail, fraction}) {
            reported.add(detail == null ? label : '$label|$detail');
          },
          reportItems: ({required completed, required total}) {
            reported.add('items:$completed/$total');
          },
        ),
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
          expect(isCancelled(), isFalse);
          return const ImportSummary(succeeded: 2);
        },
      );

      expect(summary.succeeded, 2);
      expect(reported, contains('one.txt'));
      expect(reported, contains('items:1/2'));
      expect(reported, contains('Transferring|50 / 100 bytes'));
    });

    test('execute observes cancellation from ctx', () async {
      final ctx = InstallJobContext();
      var cancelled = false;

      final summary = await runner.execute(
        plan: _largeLocalPlan(),
        ctx: ctx,
        progressStreamOverride: const Stream.empty(),
        runImport: ({required isCancelled}) async {
          ctx.requestCancel();
          await Future<void>.delayed(Duration.zero);
          cancelled = isCancelled();
          return const ImportSummary(succeeded: 1, cancelled: true);
        },
      );

      expect(cancelled, isTrue);
      expect(summary.cancelled, isTrue);
    });

    test('run throws InstallJobCancelledException for cancelled summary', () async {
      final key = InstallJobKeys.fileImport('ws-1', 'hash');
      final spec = InstallJobSpec<ImportSummary>(
        key: key,
        title: 'Import',
        cancelPolicy: InstallCancelPolicy.forceKill,
        run: (ctx) async => const ImportSummary(succeeded: 1, cancelled: true),
      );

      expect(
        () => runner.run(spec, InstallJobContext()),
        throwsA(isA<InstallJobCancelledException>()),
      );
    });

    test('run throws StateError for failed summary', () async {
      final key = InstallJobKeys.fileImport('ws-1', 'hash');
      final spec = InstallJobSpec<ImportSummary>(
        key: key,
        title: 'Import',
        cancelPolicy: InstallCancelPolicy.forceKill,
        run: (ctx) async => const ImportSummary(succeeded: 1, failed: 2),
      );

      expect(
        () => runner.run(spec, InstallJobContext()),
        throwsA(isA<StateError>()),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/progress_activity/cli_provision_activity_adapter.dart';

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

void main() {
  group('CliProvisionActivityAdapter', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit cubit;
    late CliProvisionActivityAdapter adapter;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      cubit = ProgressActivityCubit(historyRecorder: recorder);
      adapter = CliProvisionActivityAdapter(cubit: cubit);
    });

    tearDown(() {
      cubit.close();
    });

    test('runTracked maps CliInstallProgress to subtitle', () async {
      await adapter.runTracked<void>(
        title: 'Install Claude on dev-box',
        workspaceId: 'ws-1',
        historyMessageFor: (_) => 'CLI ready',
        run: (onProgress) async {
          onProgress(
            const CliInstallProgress(
              phase: CliInstallPhase.checkingNpm,
              detail: 'probe',
            ),
          );
          final activity = cubit.state.activities.single;
          expect(activity.kind, ProgressActivityKind.cliProvision);
          expect(activity.workspaceId, 'ws-1');
          expect(activity.subtitle, 'Checking npm — probe');
          expect(activity.cancellable, isFalse);

          onProgress(
            const CliInstallProgress(
              phase: CliInstallPhase.installingCli,
            ),
          );
          expect(
            cubit.state.activities.single.subtitle,
            'Installing CLI',
          );
        },
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.message, 'CLI ready');
    });

    test('runTracked completes failed on error', () async {
      await expectLater(
        adapter.runTracked<void>(
          title: 'Install Claude on dev-box',
          run: (_) async => throw StateError('ssh failed'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.error);
    });
  });
}

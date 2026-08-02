import '../../cubits/progress_activity_cubit.dart';
import '../../models/progress_activity.dart';
import '../cli/installer_types.dart';

typedef CliProvisionHistoryBuilder<T> = String? Function(T result);

/// Maps CLI install / workspace provision progress to [ProgressActivityCubit].
class CliProvisionActivityAdapter {
  CliProvisionActivityAdapter({required ProgressActivityCubit cubit})
    : _cubit = cubit;

  final ProgressActivityCubit _cubit;

  Future<T> runTracked<T>({
    required String title,
    required Future<T> Function(void Function(CliInstallProgress) onProgress)
    run,
    CliProvisionHistoryBuilder<T>? historyMessageFor,
    String? workspaceId,
    bool cancellable = false,
  }) async {
    final activityId = _newActivityId();

    try {
      final now = DateTime.now();
      _cubit.start(
        ProgressActivity(
          id: activityId,
          kind: ProgressActivityKind.cliProvision,
          title: title,
          workspaceId: workspaceId,
          phase: ProgressActivityPhase.running,
          cancellable: cancellable,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await run(
        (progress) => _applyProgress(activityId, progress),
      );

      _cubit.complete(
        activityId,
        outcome: ProgressActivityPhase.succeeded,
        historyTitle: title,
        historyMessage: historyMessageFor?.call(result),
      );
      return result;
    } catch (error, stackTrace) {
      _cubit.complete(
        activityId,
        outcome: ProgressActivityPhase.failed,
        historyTitle: title,
        errorMessage: error.toString(),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _applyProgress(String activityId, CliInstallProgress progress) {
    final detail = progress.detail?.trim();
    final phaseLabel = _phaseLabel(progress.phase);
    final subtitle = isUserFacingCliInstallDetail(detail)
        ? '$phaseLabel — $detail'
        : phaseLabel;
    _cubit.update(activityId, subtitle: subtitle);
  }

  String _phaseLabel(CliInstallPhase phase) => switch (phase) {
    CliInstallPhase.checkingNpm => 'Checking npm',
    CliInstallPhase.bootstrappingNode => 'Bootstrapping Node',
    CliInstallPhase.installingCli => 'Installing CLI',
    CliInstallPhase.locatingExecutable => 'Locating executable',
    CliInstallPhase.syncingRemoteWorkspace => 'Syncing remote workspace',
  };

  String _newActivityId() =>
      'cli-provision-${DateTime.now().microsecondsSinceEpoch}';
}

import 'dart:async';

import '../../cubits/progress_activity_cubit.dart';
import '../../models/progress_activity.dart';

/// Maps app update download/install progress to [ProgressActivityCubit].
class AppUpdateActivityAdapter {
  AppUpdateActivityAdapter({required ProgressActivityCubit cubit})
    : _cubit = cubit;

  final ProgressActivityCubit _cubit;

  String startDownload({
    required String title,
    String? subtitle,
    bool cancellable = false,
    FutureOr<void> Function()? onCancelRequested,
  }) {
    final activityId = _newActivityId();
    final now = DateTime.now();
    _cubit.start(
      ProgressActivity(
        id: activityId,
        kind: ProgressActivityKind.appUpdate,
        title: title,
        subtitle: subtitle,
        phase: ProgressActivityPhase.running,
        fraction: 0,
        cancellable: cancellable,
        createdAt: now,
        updatedAt: now,
      ),
      onCancelRequested: cancellable ? onCancelRequested : null,
    );
    return activityId;
  }

  void updateDownloadProgress(String activityId, double fraction) {
    _cubit.update(
      activityId,
      fraction: fraction.clamp(0.0, 1.0),
    );
  }

  void beginInstalling(String activityId, {required String subtitle}) {
    _cubit.update(
      activityId,
      subtitle: subtitle,
      clearFraction: true,
      cancellable: false,
    );
  }

  void completeSucceeded(
    String activityId, {
    required String historyTitle,
    String? historyMessage,
  }) {
    _cubit.complete(
      activityId,
      outcome: ProgressActivityPhase.succeeded,
      historyTitle: historyTitle,
      historyMessage: historyMessage,
    );
  }

  void completeFailed(
    String activityId, {
    required String historyTitle,
    String? errorMessage,
  }) {
    _cubit.complete(
      activityId,
      outcome: ProgressActivityPhase.failed,
      historyTitle: historyTitle,
      errorMessage: errorMessage,
    );
  }

  void completeCancelled(
    String activityId, {
    required String historyTitle,
    String? historyMessage,
  }) {
    _cubit.complete(
      activityId,
      outcome: ProgressActivityPhase.cancelled,
      historyTitle: historyTitle,
      historyMessage: historyMessage,
    );
  }

  String _newActivityId() =>
      'app-update-${DateTime.now().microsecondsSinceEpoch}';
}

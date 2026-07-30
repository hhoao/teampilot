import '../../cubits/progress_activity_cubit.dart';
import '../../models/progress_activity.dart';
import '../team/team_clone_service.dart';

typedef HubCloneHistoryBuilder<T> = String? Function(T result);

typedef HubCloneOutcomeBuilder<T> = ProgressActivityPhase Function(T result);

/// Maps hub clone / expert-hub dependency pulls to [ProgressActivityCubit].
class HubCloneActivityAdapter {
  HubCloneActivityAdapter({required ProgressActivityCubit cubit})
    : _cubit = cubit;

  final ProgressActivityCubit _cubit;

  Future<T> runTracked<T>({
    required String title,
    required Future<T> Function(void Function(CloneProgress) onProgress) run,
    HubCloneOutcomeBuilder<T>? outcomeFor,
    HubCloneHistoryBuilder<T>? historyMessageFor,
    String? workspaceId,
  }) async {
    final activityId = _newActivityId();

    try {
      final now = DateTime.now();
      _cubit.start(
        ProgressActivity(
          id: activityId,
          kind: ProgressActivityKind.hubClone,
          title: title,
          workspaceId: workspaceId,
          phase: ProgressActivityPhase.running,
          cancellable: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await run(_onCloneProgress(activityId));

      final outcome =
          outcomeFor?.call(result) ?? ProgressActivityPhase.succeeded;
      _cubit.complete(
        activityId,
        outcome: outcome,
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

  void Function(CloneProgress) _onCloneProgress(String activityId) {
    return (CloneProgress progress) {
      final hasTotal = progress.total > 0;
      _cubit.update(
        activityId,
        subtitle: progress.message.isNotEmpty ? progress.message : null,
        clearSubtitle: progress.message.isEmpty,
        completedItems: hasTotal ? progress.done : null,
        clearCompletedItems: !hasTotal,
        totalItems: hasTotal ? progress.total : null,
        clearTotalItems: !hasTotal,
        fraction: hasTotal
            ? (progress.done / progress.total).clamp(0.0, 1.0)
            : null,
        clearFraction: !hasTotal,
      );
    };
  }

  String _newActivityId() => 'hub-clone-${DateTime.now().microsecondsSinceEpoch}';
}

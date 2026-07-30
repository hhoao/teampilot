import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../cubits/progress_activity_cubit.dart';
import '../../models/progress_activity.dart';

typedef PackAcquireStepReporter = void Function({
  String? subtitle,
  int? completedSteps,
  int? totalSteps,
});

typedef PackAcquireHistoryBuilder<T> = String? Function(T result);

typedef PackAcquireOutcomeBuilder<T> = ProgressActivityPhase Function(T result);

/// Maps skill / plugin / extension acquisition to [ProgressActivityCubit].
class PackAcquireActivityAdapter {
  PackAcquireActivityAdapter({required ProgressActivityCubit cubit})
    : _cubit = cubit;

  final ProgressActivityCubit _cubit;

  Future<T> runTracked<T>({
    required ProgressActivityKind kind,
    required String title,
    required Future<T> Function(PackAcquireStepReporter onStep) run,
    PackAcquireOutcomeBuilder<T>? outcomeFor,
    PackAcquireHistoryBuilder<T>? historyMessageFor,
    String? workspaceId,
    bool cancellable = false,
    FutureOr<void> Function()? onCancelRequested,
  }) async {
    assert(kind == ProgressActivityKind.packAcquire);
    final activityId = _newActivityId();
    final cancelRequested = ValueNotifier<bool>(false);

    try {
      final now = DateTime.now();
      _cubit.start(
        ProgressActivity(
          id: activityId,
          kind: kind,
          title: title,
          workspaceId: workspaceId,
          phase: ProgressActivityPhase.running,
          cancellable: cancellable,
          createdAt: now,
          updatedAt: now,
        ),
        onCancelRequested: cancellable
            ? () {
                cancelRequested.value = true;
                final hook = onCancelRequested;
                if (hook != null) {
                  final result = hook();
                  if (result is Future<void>) {
                    unawaited(result);
                  }
                }
              }
            : null,
      );

      final result = await run(_onStep(activityId));

      final outcome =
          outcomeFor?.call(result) ?? ProgressActivityPhase.succeeded;
      _cubit.complete(
        activityId,
        outcome: outcome,
        historyTitle: title,
        historyMessage: historyMessageFor?.call(result),
        errorMessage: outcome == ProgressActivityPhase.failed
            ? historyMessageFor?.call(result)
            : null,
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
    } finally {
      cancelRequested.dispose();
    }
  }

  PackAcquireStepReporter _onStep(String activityId) {
    return ({
      String? subtitle,
      int? completedSteps,
      int? totalSteps,
    }) {
      final hasTotal = totalSteps != null && totalSteps > 0;
      _cubit.update(
        activityId,
        subtitle: subtitle,
        clearSubtitle: subtitle == null,
        completedItems: hasTotal ? completedSteps : null,
        clearCompletedItems: !hasTotal,
        totalItems: hasTotal ? totalSteps : null,
        clearTotalItems: !hasTotal,
        fraction: hasTotal && completedSteps != null
            ? (completedSteps / totalSteps).clamp(0.0, 1.0)
            : null,
        clearFraction: !hasTotal,
      );
    };
  }

  String _newActivityId() =>
      'pack-acquire-${DateTime.now().microsecondsSinceEpoch}';
}

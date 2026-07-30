import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../models/progress_activity.dart';
import '../services/notification/notification_recorder.dart';

class ProgressActivityState extends Equatable {
  const ProgressActivityState({this.activities = const []});

  final List<ProgressActivity> activities;

  List<ProgressActivity> forWorkspace(String? workspaceId) {
    return activities
        .where(
          (activity) =>
              activity.workspaceId == null ||
              activity.workspaceId == workspaceId,
        )
        .toList(growable: false);
  }

  @override
  List<Object?> get props => [activities];
}

class ProgressActivityCubit extends Cubit<ProgressActivityState> {
  ProgressActivityCubit({required NotificationRecorder historyRecorder})
    : _historyRecorder = historyRecorder,
      super(const ProgressActivityState());

  final NotificationRecorder _historyRecorder;
  final Map<String, FutureOr<void> Function()?> _cancelHooks = {};
  final Set<String> _cancelInvoked = {};

  void start(
    ProgressActivity activity, {
    FutureOr<void> Function()? onCancelRequested,
  }) {
    final existingIndex = state.activities.indexWhere(
      (entry) => entry.id == activity.id,
    );
    if (existingIndex >= 0) {
      final existing = state.activities[existingIndex];
      final replaced = activity.copyWith(createdAt: existing.createdAt);
      final activities = List<ProgressActivity>.from(state.activities)
        ..[existingIndex] = replaced;
      _cancelHooks[activity.id] = onCancelRequested;
      _cancelInvoked.remove(activity.id);
      emit(ProgressActivityState(activities: activities));
      return;
    }

    _cancelHooks[activity.id] = onCancelRequested;
    _cancelInvoked.remove(activity.id);
    final activities = [...state.activities, activity]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    emit(ProgressActivityState(activities: activities));
  }

  void update(
    String id, {
    String? title,
    String? subtitle,
    bool clearSubtitle = false,
    ProgressActivityPhase? phase,
    double? fraction,
    bool clearFraction = false,
    int? completedItems,
    bool clearCompletedItems = false,
    int? totalItems,
    bool clearTotalItems = false,
    int? bytesDone,
    bool clearBytesDone = false,
    int? bytesTotal,
    bool clearBytesTotal = false,
    bool? cancellable,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    final index = state.activities.indexWhere((entry) => entry.id == id);
    if (index < 0) return;

    final current = state.activities[index];
    final updated = ProgressActivity(
      id: current.id,
      kind: current.kind,
      title: title ?? current.title,
      subtitle: clearSubtitle ? null : (subtitle ?? current.subtitle),
      workspaceId: current.workspaceId,
      phase: phase ?? current.phase,
      fraction: clearFraction ? null : (fraction ?? current.fraction),
      completedItems: clearCompletedItems
          ? null
          : (completedItems ?? current.completedItems),
      totalItems: clearTotalItems ? null : (totalItems ?? current.totalItems),
      bytesDone: clearBytesDone ? null : (bytesDone ?? current.bytesDone),
      bytesTotal: clearBytesTotal ? null : (bytesTotal ?? current.bytesTotal),
      cancellable: cancellable ?? current.cancellable,
      detailOpen: current.detailOpen,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? current.errorMessage),
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );

    final activities = List<ProgressActivity>.from(state.activities)
      ..[index] = updated;
    emit(ProgressActivityState(activities: activities));
  }

  void requestCancel(String id) {
    final index = state.activities.indexWhere((entry) => entry.id == id);
    if (index < 0) return;

    final current = state.activities[index];
    if (current.phase == ProgressActivityPhase.cancelling) return;

    final hook = _cancelHooks[id];
    if (!current.cancellable || hook == null) {
      assert(() {
        if (current.cancellable && hook == null) {
          debugPrint(
            'ProgressActivityCubit.requestCancel: cancellable activity '
            '$id missing onCancelRequested hook',
          );
          return false;
        }
        return true;
      }());
      return;
    }

    final activities = List<ProgressActivity>.from(state.activities)
      ..[index] = current.copyWith(
        phase: ProgressActivityPhase.cancelling,
        updatedAt: DateTime.now(),
      );
    emit(ProgressActivityState(activities: activities));

    if (_cancelInvoked.add(id)) {
      final result = hook();
      if (result is Future<void>) {
        unawaited(result);
      }
    }
  }

  void setDetailOpen(String id, bool open) {
    final index = state.activities.indexWhere((entry) => entry.id == id);
    if (index < 0) return;

    final current = state.activities[index];
    if (current.detailOpen == open) return;

    final activities = List<ProgressActivity>.from(state.activities)
      ..[index] = current.copyWith(
        detailOpen: open,
        updatedAt: DateTime.now(),
      );
    emit(ProgressActivityState(activities: activities));
  }

  void complete(
    String id, {
    required ProgressActivityPhase outcome,
    String? errorMessage,
    String? historyTitle,
    String? historyMessage,
  }) {
    assert(
      outcome == ProgressActivityPhase.succeeded ||
          outcome == ProgressActivityPhase.failed ||
          outcome == ProgressActivityPhase.cancelled,
    );

    final index = state.activities.indexWhere((entry) => entry.id == id);
    if (index < 0) return;

    final current = state.activities[index];
    final activities = List<ProgressActivity>.from(state.activities)
      ..removeAt(index);
    _cancelHooks.remove(id);
    _cancelInvoked.remove(id);
    emit(ProgressActivityState(activities: activities));

    final variant = switch (outcome) {
      ProgressActivityPhase.succeeded => TpToastVariant.success,
      ProgressActivityPhase.failed => TpToastVariant.error,
      ProgressActivityPhase.cancelled => TpToastVariant.warning,
      _ => TpToastVariant.info,
    };

    final message =
        historyMessage ??
        errorMessage ??
        current.errorMessage ??
        current.subtitle ??
        current.title;
    final title = historyTitle ?? current.title;

    _historyRecorder.record(
      message: message,
      variant: variant,
      title: title,
    );
  }

  @override
  Future<void> close() {
    _cancelHooks.clear();
    _cancelInvoked.clear();
    return super.close();
  }
}

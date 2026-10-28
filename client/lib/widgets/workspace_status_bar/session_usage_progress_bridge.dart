import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/progress_activity_cubit.dart';
import '../../cubits/session_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/progress_activity.dart';
import '../../services/usage/usage_sync_control.dart';

/// Mirrors the app-level usage sync into the global progress activities so the
/// bottom status bar and notification center show it without the usage page
/// being open.
///
/// Titles/subtitles are localized here because the cubit has no BuildContext.
/// The usage page still owns its header progress; this bridge is the status-bar
/// projection only.
class SessionUsageProgressBridge extends StatefulWidget {
  const SessionUsageProgressBridge({required this.child, super.key});

  static const activityId = 'session-usage-sync';

  final Widget child;

  @override
  State<SessionUsageProgressBridge> createState() =>
      _SessionUsageProgressBridgeState();
}

class _SessionUsageProgressBridgeState
    extends State<SessionUsageProgressBridge> {
  bool _active = false;
  bool _primed = false;
  SessionUsageCubit? _usage;
  ProgressActivityCubit? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _usage = _maybeRead<SessionUsageCubit>();
    _progress = _maybeRead<ProgressActivityCubit>();
    if (_primed || _usage == null || _progress == null) return;
    _primed = true;
    // The sync may already be in flight when the home shell mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final usage = _usage;
      if (usage != null) _handle(usage.state);
    });
  }

  T? _maybeRead<T extends Object>() {
    try {
      return context.read<T>();
    } on Object {
      return null;
    }
  }

  void _handle(SessionUsageState state) {
    if (!mounted) return;
    final progressCubit = _progress;
    if (progressCubit == null) return;
    if (state.isSyncing) {
      final l10n = context.l10n;
      final progress = state.syncProgress;
      final subtitle = progress == null
          ? l10n.sessionUsageSyncPreparing
          : l10n.sessionUsageSyncProgress(
              progress.targetsDone,
              progress.targetsTotal,
              progress.inserted,
            );
      final fraction = _fraction(progress);
      if (!_active) {
        _active = true;
        final now = DateTime.now();
        progressCubit.start(
          ProgressActivity(
            id: SessionUsageProgressBridge.activityId,
            kind: ProgressActivityKind.sessionUsage,
            title: l10n.sessionUsageProgressTitle,
            subtitle: subtitle,
            phase: ProgressActivityPhase.running,
            fraction: fraction,
            cancellable: true,
            createdAt: now,
            updatedAt: now,
          ),
          onCancelRequested: () => _usage?.cancelSync(),
        );
      } else {
        progressCubit.update(
          SessionUsageProgressBridge.activityId,
          subtitle: subtitle,
          fraction: fraction,
          clearFraction: fraction == null,
        );
      }
      return;
    }

    if (!_active) return;
    _active = false;
    final l10n = context.l10n;
    final phase = state.syncCancelled
        ? ProgressActivityPhase.cancelled
        : state.syncFailed
        ? ProgressActivityPhase.failed
        : ProgressActivityPhase.succeeded;
    progressCubit.complete(
      SessionUsageProgressBridge.activityId,
      outcome: phase,
      errorMessage: phase == ProgressActivityPhase.failed
          ? l10n.sessionUsageSyncFatal
          : null,
      recordHistory: false,
    );
  }

  double? _fraction(UsageSyncProgress? progress) {
    if (progress == null || progress.targetsTotal <= 0) return null;
    return (progress.targetsDone / progress.targetsTotal).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_usage == null || _progress == null) return widget.child;
    return BlocListener<SessionUsageCubit, SessionUsageState>(
      listenWhen: (previous, current) =>
          previous.isSyncing != current.isSyncing ||
          previous.syncProgress != current.syncProgress ||
          previous.syncFailed != current.syncFailed ||
          previous.syncCancelled != current.syncCancelled,
      listener: (context, state) => _handle(state),
      child: widget.child,
    );
  }
}

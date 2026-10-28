import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/progress_activity_cubit.dart';
import '../../models/progress_activity.dart';
import '../../services/storage/app_paths.dart';
import '../app_toast/app_toast.dart';

/// Runs a user-triggered git operation while showing the workspace status-bar
/// progress pill, then reports the outcome.
///
/// - The pill is scoped to [workspaceId] when known (app-global otherwise) and
///   keyed per repository, so a new operation replaces a stale one.
/// - Success shows [doneMessage] as a success toast; the toast is the single
///   notification-history record (`recordHistory: false` on the activity).
/// - Failures are surfaced by the caller's existing `errorMessage` → toast
///   path, so this helper stays quiet about them.
/// - Degrades to a plain call when [ProgressActivityCubit] is unavailable
///   (widget tests, mobile without a status bar).
Future<bool> runGitOperation(
  BuildContext context, {
  required String workspaceId,
  required String repoRoot,
  required String title,
  required String doneMessage,
  bool showSuccessToast = true,
  required Future<bool> Function() body,
}) async {
  ProgressActivityCubit? progress;
  try {
    progress = context.read<ProgressActivityCubit>();
  } on Object {
    progress = null;
  }

  final id = 'git:$repoRoot';
  final now = DateTime.now();
  final scoped = workspaceId.isEmpty ? null : workspaceId;
  if (progress != null && !progress.isClosed) {
    progress.start(
      ProgressActivity(
        id: id,
        kind: ProgressActivityKind.gitOperation,
        title: title,
        subtitle: _repoName(repoRoot),
        workspaceId: scoped,
        phase: ProgressActivityPhase.running,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  var ok = false;
  try {
    ok = await body();
  } finally {
    if (progress != null && !progress.isClosed) {
      progress.complete(
        id,
        outcome: ok
            ? ProgressActivityPhase.succeeded
            : ProgressActivityPhase.failed,
        recordHistory: false,
      );
    }
  }

  if (ok && showSuccessToast && context.mounted) {
    AppToast.show(
      context,
      message: doneMessage,
      variant: TpToastVariant.success,
    );
  }
  return ok;
}

String _repoName(String repoRoot) {
  final name = AppPaths.pathContextForDataRoot(repoRoot).basename(repoRoot);
  return name.isEmpty ? repoRoot : name;
}

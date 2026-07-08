import '../../cubits/chat/model/session_open_status.dart';

/// Unified result of [SessionLaunchPipeline.run].
sealed class LaunchOutcome {}

/// Tab surfaced; maps to [SessionOpenStatus] for open/create entry points.
final class LaunchOpened extends LaunchOutcome {
  LaunchOpened(this.status);

  final SessionOpenStatus status;
}

/// Fire-and-forget launch command completed without a tab status.
final class LaunchCompleted extends LaunchOutcome {}

/// Launch aborted before side effects (e.g. already connecting).
final class LaunchSkipped extends LaunchOutcome {}

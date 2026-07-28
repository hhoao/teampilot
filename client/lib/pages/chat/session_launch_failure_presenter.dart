import '../../services/workspace/dead_ssh_target_error.dart';

enum SessionLaunchFailureActionKind { retry, remapDeadSsh }

final class SessionLaunchFailureAction {
  const SessionLaunchFailureAction({
    required this.kind,
    this.deadSshTargetId,
  });

  final SessionLaunchFailureActionKind kind;
  final String? deadSshTargetId;
}

final class SessionLaunchFailureView {
  const SessionLaunchFailureView({
    required this.message,
    required this.actions,
  });

  final String message;
  final List<SessionLaunchFailureAction> actions;
}

/// Builds a product-facing failure view from a stored launch error string.
///
/// [launchError] is expected to already be formatted via
/// `formatSessionLaunchError` when stored on the tab.
SessionLaunchFailureView? presentSessionLaunchFailure(String? launchError) {
  final message = launchError?.trim() ?? '';
  if (message.isEmpty) return null;

  final dead = deadSshTargetIdFromError(message);
  final actions = <SessionLaunchFailureAction>[
    if (dead != null)
      SessionLaunchFailureAction(
        kind: SessionLaunchFailureActionKind.remapDeadSsh,
        deadSshTargetId: dead,
      ),
    const SessionLaunchFailureAction(kind: SessionLaunchFailureActionKind.retry),
  ];
  return SessionLaunchFailureView(message: message, actions: actions);
}

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';

/// Prefer the underlying cause when dartssh2 wraps a handshake failure.
///
/// Host-key rejection closes the socket before auth completes, so callers often
/// only see [SSHAuthAbortError] unless they unwrap [SSHAuthAbortError.reason].
Object sshConnectionFailureCause(Object error) {
  if (error is SSHAuthAbortError && error.reason != null) {
    return error.reason!;
  }
  return error;
}

/// Diagnostic string for logs (includes outer + cause when nested).
String sshConnectionFailureLogMessage(Object error) {
  final cause = sshConnectionFailureCause(error);
  if (identical(cause, error)) return error.toString();
  return '$error (cause: $cause)';
}

/// Short user-facing explanation for SSH connect/test failures.
String sshConnectionFailureUserMessage(
  Object error,
  AppLocalizations l10n,
) {
  final cause = sshConnectionFailureCause(error);
  if (cause is SSHHostkeyError) {
    return l10n.sshProfileTestFailedHostKey;
  }
  if (cause is SSHAuthFailError) {
    return l10n.sshProfileTestFailedAuth;
  }
  if (error is SSHAuthAbortError || cause is SSHAuthAbortError) {
    return l10n.sshProfileTestFailedAborted(cause.toString());
  }
  return l10n.sshProfileTestFailedDetail(error.toString());
}

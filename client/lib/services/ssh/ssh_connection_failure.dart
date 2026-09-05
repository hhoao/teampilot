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
  if (isSshdPenaltyRefusal(error)) {
    return l10n.sshPenaltyRefused;
  }
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

/// OpenSSH ≥ 9.8 replies with this plain-text line instead of an SSH version
/// banner while a `PerSourcePenalties` refusal is active for our source.
const _sshdPenaltyRefusalText = 'Not allowed at this time';

/// True when [error] is an sshd `PerSourcePenalties` refusal: the version
/// exchange read the refusal text instead of an `SSH-2.0-` banner. Retrying
/// immediately only extends the penalty; callers should back off.
bool isSshdPenaltyRefusal(Object error) {
  final cause = sshConnectionFailureCause(error);
  return cause is SSHHandshakeError &&
      cause.message.contains(_sshdPenaltyRefusalText);
}

/// Maps a stored SSH error-detail string for display. Penalty refusals get a
/// localized explanation; anything else passes through.
String sshErrorDetailUserMessage(String? detail, AppLocalizations l10n) {
  final trimmed = detail?.trim();
  if (trimmed == null || trimmed.isEmpty) return '';
  if (trimmed.contains(_sshdPenaltyRefusalText)) {
    return l10n.sshPenaltyRefused;
  }
  return trimmed;
}

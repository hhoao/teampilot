import 'session_book.dart';
import 'spool.dart';
import 'upstream.dart';

/// Default idle time before a disconnected session is closed.
const acpProxyIdleTimeout = Duration(minutes: 30);

/// Whether the idle clock should advance.
///
/// True only when the phone is gone, no turn is in progress, and no
/// permission request is still waiting. A running turn or an open permission
/// must not be reaped.
bool shouldRunIdleTimer({
  required bool phoneConnected,
  required bool turnInProgress,
  required bool permissionPending,
}) {
  return !phoneConnected && !turnInProgress && !permissionPending;
}

/// Closes and deletes sessions whose idle clock has run past [idleTimeout].
///
/// Eligible only when [shouldRunIdleTimer] is true and [disconnectedSince]
/// is strictly older than [idleTimeout]. The phone, an open turn, or a
/// pending permission keeps the session. After a successful close, the
/// session is dropped from [upstreams] and [disconnectedSince] so the next
/// tick does not close it again.
Future<void> reapIdleSessions({
  required AcpProxySessionBook book,
  required AcpProxySpool spool,
  required Map<String, AcpUpstream> upstreams,
  required Map<String, DateTime> disconnectedSince,
  required DateTime now,
  required Duration idleTimeout,
  required bool Function(String sessionId) permissionPending,
}) async {
  for (final sessionId in book.sessionIds.toList()) {
    final since = disconnectedSince[sessionId];
    if (since == null) continue;
    final idle = shouldRunIdleTimer(
      phoneConnected: book.phoneConnected(sessionId),
      turnInProgress: book.turnInProgress(sessionId),
      permissionPending: permissionPending(sessionId),
    );
    if (!idle) continue;
    if (now.difference(since) <= idleTimeout) continue;
    final upstream = upstreams[sessionId];
    if (upstream != null) {
      await upstream.close();
      upstreams.remove(sessionId);
    }
    await spool.delete(sessionId);
    disconnectedSince.remove(sessionId);
  }
}

import '../ssh/ssh_transport_close.dart';
import '../ssh/worker/ssh_worker_protocol.dart';

/// Whether [error] means the storage *transport* failed (SSH/SFTP closed,
/// socket dropped) rather than the data being absent or corrupt.
///
/// Repositories legitimately treat missing or corrupt files as empty (a
/// half-written JSON is recoverable, an absent config means defaults). A
/// dropped remote transport is NOT the same thing: returning empty there makes
/// "the machine is unreachable" indistinguishable from "nothing is stored",
/// which reads to the user as lost profiles/workspaces/sessions.
///
/// Callers that tolerate data errors must rethrow transport failures instead:
///
/// ```dart
/// } on Object catch (error) {
///   if (isStorageTransportFailure(error)) rethrow;
///   return const [];
/// }
/// ```
const _workerTransportCodes = {
  'transport_closed',
  'transport_error',
  'transport_timeout',
  'storage_not_connected',
  'socket_error',
  'handshake_error',
  'connection_refused',
  'timeout',
};

bool isStorageTransportFailure(Object error) {
  if (error is SshTransportClosed) return true;
  if (error is SshWorkerCodedException &&
      _workerTransportCodes.contains(error.code)) {
    return true;
  }
  return _looksLikeClosedTransport(error.toString());
}

/// dartssh2 surfaces raw `SSHStateError`/`SftpClient` failures without a
/// structured type, so message matching is the only available signal.
bool _looksLikeClosedTransport(String message) {
  final lower = message.toLowerCase();
  return lower.contains('sftp channel closed') ||
      lower.contains('sftp client closed') ||
      lower.contains('ssh client closed') ||
      lower.contains('ssh transport closed') ||
      lower.contains('transport is closed') ||
      lower.contains('connection closed') ||
      lower.contains('socket closed') ||
      lower.contains('profile worker message channel is closed') ||
      lower.contains('ssh profile worker message channel closed') ||
      lower.contains('ssh profile worker is shutting down');
}

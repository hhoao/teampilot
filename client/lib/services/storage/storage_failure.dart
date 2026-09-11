import '../ssh/ssh_transport_close.dart';

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
bool isStorageTransportFailure(Object error) {
  if (error is SshTransportClosed) return true;
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
      lower.contains('socket closed');
}

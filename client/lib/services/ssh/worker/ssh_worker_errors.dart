import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

/// Stable error codes shared by the worker and the UI isolate.
///
/// Keep these strings in sync with the checks in
/// `services/ssh/ssh_connection_failure.dart`.
const sshWorkerErrorHostKeyRejected = 'hostkey_rejected';
const sshWorkerErrorAuthFailed = 'auth_failed';
const sshWorkerErrorAuthAborted = 'auth_aborted';
const sshWorkerErrorSshdPenalty = 'sshd_penalty';
const sshWorkerErrorConnectionRefused = 'connection_refused';
const sshWorkerErrorSocket = 'socket_error';
const sshWorkerErrorHandshake = 'handshake_error';
const sshWorkerErrorTimeout = 'timeout';
const sshWorkerErrorTransport = 'transport_error';

/// Prefix for a refused channel open; suffixed with the SSH open reason code
/// (e.g. `channel_open_2` = target connect failed). Diagnostics only.
const sshWorkerErrorChannelOpen = 'channel_open';

const _sshdPenaltyRefusalText = 'Not allowed at this time';
const _connectionRefusedErrnos = {111, 61, 10061};

/// Classifies a worker-local connection failure before it is flattened into a
/// stringly typed reply.
String sshWorkerErrorCode(Object error) {
  var cause = error;
  if (error is SSHAuthAbortError && error.reason != null) {
    cause = error.reason!;
  }
  if (cause is SSHHostkeyError) return sshWorkerErrorHostKeyRejected;
  if (cause is SSHAuthFailError) return sshWorkerErrorAuthFailed;
  if (cause is SSHAuthAbortError) return sshWorkerErrorAuthAborted;
  if (cause is SSHHandshakeError) {
    return cause.message.contains(_sshdPenaltyRefusalText)
        ? sshWorkerErrorSshdPenalty
        : sshWorkerErrorHandshake;
  }
  if (cause is SSHSocketError) {
    final inner = cause.error;
    if (inner is SocketException &&
        _connectionRefusedErrnos.contains(inner.osError?.errorCode)) {
      return sshWorkerErrorConnectionRefused;
    }
    return sshWorkerErrorSocket;
  }
  if (cause is SocketException &&
      _connectionRefusedErrnos.contains(cause.osError?.errorCode)) {
    return sshWorkerErrorConnectionRefused;
  }
  if (cause is TimeoutException) return sshWorkerErrorTimeout;
  // A refused `direct-tcpip` / channel open (e.g. the forwarded loopback port
  // is not listening: SSH_OPEN_CONNECT_FAILED=2, forwarding disabled=1,
  // resource shortage=4). Previously fell through to the opaque
  // `transport_error`, which hid the real cause; keep the SSH reason code so
  // forward failures are diagnosable.
  if (cause is SSHChannelOpenError) {
    return '${sshWorkerErrorChannelOpen}_${cause.code}';
  }
  return sshWorkerErrorTransport;
}

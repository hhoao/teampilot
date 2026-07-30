/// Why an SSH transport was torn down (local intent or inferred from the socket).
enum SshTransportCloseReason {
  userDisconnect,
  profileInvalidated,
  profileRemoved,
  runtimeContextEvicted,
  hostIdentityChanged,
  authFailed,
  disconnectAll,
  remoteFileStoreDisconnect,
  memberSessionClosed,
  remotePeerClosed,
  transportError,
}

/// Which connection plane closed (storage pool vs per-member session).
enum SshTransportPlane { storage, member }

/// Structured close signal for logs and reconnect policy.
class SshTransportClosed implements Exception {
  const SshTransportClosed({
    required this.reason,
    required this.plane,
    this.cause,
  });

  final SshTransportCloseReason reason;
  final SshTransportPlane plane;
  final Object? cause;

  bool get isGenericRemoteClose =>
      reason == SshTransportCloseReason.remotePeerClosed && cause == null;

  @override
  String toString() {
    final buffer = StringBuffer(
      'SSH transport closed (reason=${reason.name}, plane=${plane.name}',
    );
    if (cause != null) {
      buffer.write(', cause=$cause');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

bool isGenericSshTransportClose(Object error) {
  if (error is SshTransportClosed) return error.isGenericRemoteClose;
  return error is StateError && error.message == 'SSH transport closed';
}

/// Local, intentional teardowns — log at info, not warn.
bool isExpectedLocalSshTransportClose(SshTransportClosed closed) {
  switch (closed.reason) {
    case SshTransportCloseReason.userDisconnect:
    case SshTransportCloseReason.profileInvalidated:
    case SshTransportCloseReason.profileRemoved:
    case SshTransportCloseReason.runtimeContextEvicted:
    case SshTransportCloseReason.disconnectAll:
    case SshTransportCloseReason.remoteFileStoreDisconnect:
    case SshTransportCloseReason.memberSessionClosed:
      return true;
    case SshTransportCloseReason.hostIdentityChanged:
    case SshTransportCloseReason.authFailed:
    case SshTransportCloseReason.remotePeerClosed:
    case SshTransportCloseReason.transportError:
      return false;
  }
}

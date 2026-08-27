import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

class SshdPresenceSnapshot {
  const SshdPresenceSnapshot({
    required this.listening,
    required this.port,
    required this.fingerprints,
    required this.enableHint,
  });

  final bool listening;
  final int port;
  final List<String> fingerprints;
  final String enableHint;
}

typedef SshdPresenceProbe = Future<SshdPresenceSnapshot> Function();
typedef SshdTcpProbe =
    Future<bool> Function(String host, int port, Duration timeout);
typedef ReadHostFingerprints = Future<List<String>> Function();

class SshdPresence {
  SshdPresence({
    this.port = 22,
    this.timeout = const Duration(milliseconds: 300),
    SshdTcpProbe? tcpProbe,
    ReadHostFingerprints? readHostFingerprints,
    String? enableHint,
  }) : _tcpProbe = tcpProbe ?? _defaultTcpProbe,
       _readHostFingerprints =
           readHostFingerprints ??
           SshdHostKeyScanner(port: port, timeout: timeout).scan,
       _enableHint = enableHint ?? platformSshdEnableHint();

  final int port;
  final Duration timeout;
  final SshdTcpProbe _tcpProbe;
  final ReadHostFingerprints _readHostFingerprints;
  final String _enableHint;

  Future<SshdPresenceSnapshot> probe() async {
    final listening = await _tcpProbe('127.0.0.1', port, timeout);
    if (!listening) {
      return SshdPresenceSnapshot(
        listening: false,
        port: port,
        fingerprints: const [],
        enableHint: _enableHint,
      );
    }
    List<String> fingerprints;
    try {
      fingerprints = await _readHostFingerprints();
    } on Object {
      fingerprints = const [];
    }
    return SshdPresenceSnapshot(
      listening: true,
      port: port,
      fingerprints: fingerprints
          .where((value) => value.startsWith('SHA256:'))
          .toSet()
          .toList(growable: false),
      enableHint: _enableHint,
    );
  }
}

/// Reads the server identity during key exchange and closes before user auth.
class SshdHostKeyScanner {
  SshdHostKeyScanner({
    this.host = '127.0.0.1',
    this.port = 22,
    this.timeout = const Duration(milliseconds: 300),
  });

  final String host;
  final int port;
  final Duration timeout;

  Future<List<String>> scan() async {
    SSHSocket? socket;
    SSHTransport? transport;
    try {
      socket = await SSHSocket.connect(host, port, timeout: timeout);
      final captured = Completer<String>();
      transport = SSHTransport(
        socket,
        onVerifyHostKey: (_, fingerprint) {
          final identity = utf8.decode(fingerprint, allowMalformed: true);
          if (!captured.isCompleted) captured.complete(identity);
          return false;
        },
      );
      final identity = await captured.future.timeout(timeout);
      return identity.startsWith('SHA256:') ? [identity] : const [];
    } on Object {
      return const [];
    } finally {
      transport?.close();
      socket?.destroy();
    }
  }
}

String platformSshdEnableHint() {
  if (Platform.isMacOS) return 'Enable Remote Login in System Settings.';
  if (Platform.isWindows) {
    return 'Install OpenSSH Server in Optional Features, then start sshd.';
  }
  return 'Enable and start the ssh or sshd service.';
}

Future<bool> _defaultTcpProbe(String host, int port, Duration timeout) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    return true;
  } on Object {
    return false;
  } finally {
    socket?.destroy();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

typedef SshdPortProbe = Future<bool> Function();
typedef SshKeyScanRunner =
    Future<({int exitCode, String stdout, String stderr})> Function();

const int systemSshdPort = 22;

/// Parses OpenSSH key-scan output into unique SHA256 host-key fingerprints.
List<String> fingerprintsFromSshKeyScan(String stdout) {
  final fingerprints = <String>{};
  for (final line in const LineSplitter().convert(stdout)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 3) continue;

    try {
      final blob = base64.decode(parts[2]);
      final digest = crypto.sha256.convert(blob).bytes;
      fingerprints.add('SHA256:${base64.encode(digest).replaceAll('=', '')}');
    } on FormatException {
      continue;
    }
  }
  return fingerprints.toList(growable: false);
}

/// Samples whether a system OpenSSH server is reachable and has scannable keys.
class SshdPresence {
  SshdPresence({required SshdPortProbe probe, required SshKeyScanRunner scan})
    : _probe = probe,
      _scan = scan;

  final SshdPortProbe _probe;
  final SshKeyScanRunner _scan;

  Future<({bool listening, List<String> fingerprints})> sample() async {
    if (!await _probe()) {
      return (listening: false, fingerprints: const <String>[]);
    }

    final result = await _scan();
    final fingerprints = fingerprintsFromSshKeyScan(result.stdout);
    if (fingerprints.isEmpty) {
      return (listening: false, fingerprints: const <String>[]);
    }
    return (listening: true, fingerprints: fingerprints);
  }
}

/// Creates a probe that connects to the IPv4 loopback OpenSSH port.
SshdPortProbe loopbackSshdProbe({
  Duration timeout = const Duration(seconds: 1),
}) {
  return () async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        systemSshdPort,
        timeout: timeout,
      );
      await socket.close();
      return true;
    } on Object {
      return false;
    }
  };
}

/// Creates an OpenSSH host-key scanner backed by the supplied process runner.
SshKeyScanRunner sshKeyScanRunner({
  required Future<({int exitCode, String stdout, String stderr})> Function(
    String executable,
    List<String> arguments,
  )
  run,
}) {
  return () async {
    try {
      return await run('ssh-keyscan', const [
        '-t',
        'ed25519,ecdsa,rsa',
        '-p',
        '22',
        '-T',
        '3',
        '127.0.0.1',
      ]);
    } on Object {
      return (exitCode: 127, stdout: '', stderr: '');
    }
  };
}

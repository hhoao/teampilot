/// Differential audit runner: brings up the harness servers
/// ([startAuditServers]) and runs the selected audit areas, or `--smoke` to
/// prove the harness talks to both servers (publickey login + `echo ok`).
///
///   dart run tool/differential/run_audit.dart --smoke
///   dart run tool/differential/run_audit.dart --area a
///
/// Exits 0 with `SKIPPED:` when the system sshd is unavailable, so the
/// package suite stays green on machines without OpenSSH.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart' show SSHClient, SSHKeyPair, SSHSocket;

import 'audit_harness.dart';

/// What the OpenSSH reference says should happen on one audit row.
class OpenSshExpectation {
  const OpenSshExpectation(this.citation, this.predicted);

  /// Where in the OpenSSH source the behavior is anchored (file:line or
  /// function reference into the checkout at `--openssh-src`).
  final String citation;

  /// The predicted behavior in one short phrase.
  final String predicted;

  @override
  String toString() => '$predicted [$citation]';
}

/// One differential audit row: the reference expectation, what the system
/// sshd actually did, and what tp_sshd actually did.
class RowResult {
  const RowResult({
    required this.id,
    required this.expected,
    required this.openSshActual,
    required this.tpSshdActual,
  });

  final String id;
  final OpenSshExpectation expected;
  final String openSshActual;
  final String tpSshdActual;

  /// Whether both servers behaved identically (the audit question; a match
  /// is not necessarily correct — both could deviate from [expected]).
  bool get matches => openSshActual == tpSshdActual;
}

/// Runs one audit area against the live servers.
typedef AreaRunner = Future<List<RowResult>> Function(AuditServers servers);

/// Audit area titles, keyed by the `--area` letter.
const Map<String, String> areaTitles = {
  'a': 'Area A — malformed input',
  'b': 'Area B — rekey timing',
  'c': 'Area C — window handling',
  'd': 'Area D — close races',
  'e': 'Area E — timing surfaces',
};

/// Registered area implementations. Tasks 2–5 add their runners here; until
/// then every area reports that no rows exist.
final Map<String, AreaRunner> areaRunners = {};

Future<void> main(List<String> args) async {
  var smoke = false;
  var area = 'all';
  var opensshSrc =
      '${Platform.environment['HOME']}/.cache/openssh-portable';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--smoke':
        smoke = true;
      case '--area':
        if (++i >= args.length) _usage('missing value for --area');
        area = args[i];
        if (!areaTitles.containsKey(area) && area != 'all') {
          _usage('unknown area "$area" (expected a|b|c|d|e|all)');
        }
      case '--openssh-src':
        if (++i >= args.length) _usage('missing value for --openssh-src');
        opensshSrc = args[i];
      case '--help' || '-h':
        _printUsage();
        return;
      default:
        _usage('unknown option: ${args[i]}');
    }
  }

  await _printSourceAnchor(opensshSrc);

  final AuditServers servers;
  try {
    servers = await startAuditServers();
  } on SshdUnavailableException catch (error) {
    print('SKIPPED: system sshd not available ($error)');
    return;
  }

  // exit() does not run finally blocks, so the servers are closed before it.
  var exitCode = 0;
  try {
    if (smoke) {
      exitCode = await _runSmoke(servers) ? 0 : 1;
    } else {
      await _runAreas(servers, area);
    }
  } finally {
    await servers.close();
  }
  exit(exitCode);
}

Never _usage(String problem) {
  print('error: $problem');
  _printUsage();
  exit(64);
}

void _printUsage() {
  print('''
usage: dart run tool/differential/run_audit.dart [--smoke] [--area a|b|c|d|e|all] [--openssh-src <path>]

  --smoke         publickey login + exec 'echo ok' against BOTH servers
  --area          audit area to run (default: all)
  --openssh-src   OpenSSH reference checkout (default: ~/.cache/openssh-portable)
''');
}

/// Reports which OpenSSH version the row citations will refer to.
Future<void> _printSourceAnchor(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    print(
      'OpenSSH reference source not found at $path '
      '(row citations will lack a source anchor)',
    );
    return;
  }
  final result = await () async {
    try {
      return await Process.run('git', ['-C', path, 'describe', '--tags']);
    } on ProcessException {
      // A machine without git (the same minimal class that lacks sshd) must
      // still get a clean skip, not a crash before the servers even start.
      return null;
    }
  }();
  final tag = result != null && result.exitCode == 0
      ? (result.stdout as String).trim()
      : 'unknown tag';
  print('OpenSSH reference source: $path ($tag)');
}

// ---------------------------------------------------------------------------
// Smoke
// ---------------------------------------------------------------------------

Future<bool> _runSmoke(AuditServers servers) async {
  print('# tp_sshd differential harness smoke');
  print('username : ${servers.username}');
  print('OpenSSH  : 127.0.0.1:${servers.sshdPort}');
  print('tp_sshd  : 127.0.0.1:${servers.tpdPort}');
  print('audit dir: ${servers.tempDir.path} (sshd log: ${servers.sshdLogPath})');

  final results = <({String label, bool ok})>[];
  results.add(
    await _smokeLoginExec('OpenSSH', servers.sshdPort, servers),
  );
  results.add(await _smokeLoginExec('tp_sshd', servers.tpdPort, servers));

  print('');
  print('| server | login | exec `echo ok` |');
  print('|--------|-------|----------------|');
  for (final result in results) {
    print('| ${result.label} | ${result.ok ? 'ok' : 'FAILED'} | ${result.ok ? '`ok`' : 'failed'} |');
  }
  return results.every((result) => result.ok);
}

/// Full publickey login + `exec 'echo ok'` against one server, the
/// `tp1:{"query":"host-info"}`-equivalent smoke row.
Future<({String label, bool ok})> _smokeLoginExec(
  String label,
  int port,
  AuditServers servers,
) async {
  try {
    final identity = SSHKeyPair.fromPem(servers.deviceKeyPem).single;
    final client = SSHClient(
      await SSHSocket.connect('127.0.0.1', port),
      username: servers.username,
      identities: [identity],
      onVerifyHostKey: (_, __) => true,
    );
    // The transport's done future can complete with the server's error
    // after a successful session; a dropped reference must not become an
    // unhandled async error.
    client.done.catchError((_) {});
    try {
      await client.authenticated.timeout(const Duration(seconds: 10));
      // stdout only: the login shell's rc files may write to stderr under
      // the system sshd (which runs commands via the user's shell), and
      // that noise is not part of the exec result under test.
      final output = await client
          .run('echo ok', stderr: false)
          .timeout(const Duration(seconds: 10));
      final text = utf8.decode(output).trim();
      final ok = text == 'ok';
      print(
        '$label: publickey login ok, exec "echo ok" -> '
        '"$text"${ok ? '' : ' (expected "ok")'}',
      );
      return (label: label, ok: ok);
    } finally {
      client.close();
    }
  } on Object catch (error) {
    print('$label: FAILED: $error');
    return (label: label, ok: false);
  }
}

// ---------------------------------------------------------------------------
// Areas
// ---------------------------------------------------------------------------

Future<void> _runAreas(AuditServers servers, String selection) async {
  final selected =
      selection == 'all' ? areaTitles.keys.toList() : [selection];
  var ranAny = false;
  for (final key in selected) {
    final runner = areaRunners[key];
    if (runner == null) {
      print('(area $key — ${areaTitles[key]}: no rows registered yet)');
      continue;
    }
    ranAny = true;
    print('');
    print('## ${areaTitles[key]}');
    final rows = await runner(servers);
    print(_markdownTable(rows));
  }
  if (!ranAny) {
    print('(no audit rows registered — run --smoke to verify the harness)');
  }
}

String _markdownTable(List<RowResult> rows) {
  final buffer = StringBuffer(
    '| id | expected (OpenSSH) | OpenSSH actual | tp_sshd actual | diff |\n'
    '|----|--------------------|----------------|----------------|------|\n',
  );
  for (final row in rows) {
    buffer.write(
      '| ${_cell(row.id)} '
      '| ${_cell('${row.expected.predicted} [${row.expected.citation}]')} '
      '| ${_cell(row.openSshActual)} '
      '| ${_cell(row.tpSshdActual)} '
      '| ${row.matches ? 'same' : 'DIFF'} |\n',
    );
  }
  return buffer.toString();
}

String _cell(String text) => text.replaceAll('|', '\\|').replaceAll('\n', ' ');

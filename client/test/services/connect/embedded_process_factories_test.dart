@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/embedded_process_factories.dart';
import 'package:tp_sshd/tp_sshd.dart' show SSHPtyDimensions;

void main() {
  test('shell selection is PowerShell on Windows, \$SHELL elsewhere', () {
    // EmbeddedShellSelection takes the platform as a parameter.
    expect(EmbeddedShellSelection.executable(platform: 'windows'), 'powershell.exe');
    expect(
      EmbeddedShellSelection.arguments(platform: 'windows'),
      ['-NoLogo'],
    );
    expect(
      EmbeddedShellSelection.executable(platform: 'linux', shellEnv: '/bin/zsh'),
      '/bin/zsh',
    );
    expect(
      EmbeddedShellSelection.executable(platform: 'linux', shellEnv: null),
      '/bin/bash',
    );
    expect(EmbeddedShellSelection.arguments(platform: 'linux'), isEmpty);
  });

  test('toolchain PATH is prepended, existing PATH preserved', () {
    final env = EmbeddedSpawnEnvironment.mergeWithToolchainPath(
      {'PATH': '/usr/bin', 'HOME': '/home/u'},
      toolchainBin: '/home/u/.local/share/com.hhoa.teampilot/toolchain/node/current/bin',
    );
    // POSIX mirrors the remote export being replaced: toolchain bin plus
    // ~/.local/bin (npm --prefix ~/.local shims), then the inherited PATH.
    expect(
      env['PATH'],
      '/home/u/.local/share/com.hhoa.teampilot/toolchain/node/current/bin'
      ':/home/u/.local/bin:/usr/bin',
    );
    expect(env['HOME'], '/home/u');
  });

  test('windows PATH merge uses the ; separator without ~/.local/bin', () {
    final env = EmbeddedSpawnEnvironment.mergeWithToolchainPath(
      {'PATH': r'C:\Windows', 'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
      toolchainBin: r'C:\Users\u\AppData\Local\com.hhoa.teampilot\toolchain\node\v24.15.0',
      isWindows: true,
    );
    expect(
      env['PATH'],
      r'C:\Users\u\AppData\Local\com.hhoa.teampilot\toolchain\node\v24.15.0'
      r';C:\Windows',
    );
  });

  test('pty factory passes dimensions and env through the spawner', () async {
    final spawned = <Object?>[];
    var fake = _FakePtyLike();
    final factory = embeddedPtyFactory(
      spawner: ({required executable, required arguments, required environment, required columns, required rows}) async {
        spawned.addAll([executable, arguments, environment, columns, rows]);
        fake = _FakePtyLike();
        return fake;
      },
    );
    final pty = await factory(const SSHPtyDimensions(
      columns: 80, rows: 24, environment: {'TERM': 'xterm-256color'},
    ));
    expect(spawned[3], 80);
    expect(spawned[4], 24);
    expect((spawned[2] as Map<String, String>)['TERM'], 'xterm-256color');
    pty!.resize(100, 30); // forwarded
    pty.kill();
    expect(fake.resizes, [
      [100, 30],
    ]);
    expect(fake.killed, isTrue);
  });

  test('pty signal maps RFC 4254 names to ProcessSignal, unknown names drop', () async {
    var fake = _FakePtyLike();
    final factory = embeddedPtyFactory(
      spawner: ({required executable, required arguments, required environment, required columns, required rows}) async {
        fake = _FakePtyLike();
        return fake;
      },
    );
    final pty = await factory(const SSHPtyDimensions(columns: 80, rows: 24));
    pty!.signal('INT');
    pty.signal('TERM');
    pty.signal('HUP');
    pty.signal('KILL');
    pty.signal('USR1'); // unknown: logged and dropped, no crash
    expect(fake.signals, [
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sighup,
      ProcessSignal.sigkill,
    ]);
  });

  test('pty factory refuses on spawn failure instead of throwing', () async {
    final factory = embeddedPtyFactory(
      spawner: ({required executable, required arguments, required environment, required columns, required rows}) async {
        throw ProcessException('shell', [], 'no such file');
      },
    );
    final pty = await factory(const SSHPtyDimensions(columns: 80, rows: 24));
    expect(pty, isNull);
  });
}

/// Records resize/kill/write calls; streams and exit code never emit.
class _FakePtyLike implements PtyLike {
  final resizes = <List<int>>[];
  final signals = <ProcessSignal>[];
  final writes = <List<int>>[];
  bool killed = false;

  @override
  Stream<Uint8List> get output => const Stream.empty();

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  void write(Uint8List data) => writes.add(List<int>.of(data));

  @override
  void resize(int columns, int rows) => resizes.add([columns, rows]);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    signals.add(signal);
    return true;
  }
}

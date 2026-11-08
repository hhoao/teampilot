import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/antigravity/provider/antigravity_remote_login_dialog.dart';
import 'package:teampilot/services/ssh/ssh_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';

void main() {
  testWidgets('remote login starts agy with isolated HOME and verifies models', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final session = _FakeMemberSession();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AntigravityRemoteLoginDialog(
          provider: const AppProviderConfig(
            id: 'antigravity',
            cli: CliTool.antigravity,
            name: 'Antigravity',
            isOfficial: true,
          ),
          executable: 'agy',
          profile: const SshProfile(
            id: 'p1',
            name: 'host',
            host: 'host',
            username: 'dev',
            authType: SshAuthType.password,
          ),
          openSession: (_) async => session,
          terminalBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.ptyCommand, isNotNull);
    expect(session.ptyCommand, contains('exec '));
    expect(session.ptyCommand, contains('HOME='));
    expect(session.ptyCommand, contains('GEMINI_HOME='));

    await tester.tap(find.byKey(const Key('antigravityRemoteLoginDone')));
    await tester.pumpAndSettle();

    expect(session.verified, isTrue);
    expect(session.closed, isTrue);
  });
}

class _FakeMemberSession implements SshMemberSession {
  String? ptyCommand;
  bool verified = false;
  bool closed = false;

  @override
  Future<String> run(String command) async {
    if (command.contains(r'printf %s "$HOME"')) return '/home/dev';
    return '';
  }

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool stderr = true,
  }) async {
    if (command.contains(' models')) verified = true;
    final stdout = command.contains('command -v agy')
        ? const [97, 103, 121] // agy
        : const <int>[];
    return SSHRunResult(
      output: Uint8List.fromList(stdout),
      stdout: Uint8List.fromList(stdout),
      stderr: Uint8List(0),
      exitCode: 0,
      exitSignal: null,
    );
  }

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async {
    ptyCommand = command;
    return _FakePtyChannel();
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePtyChannel implements SshWorkerPtyChannel {
  final _output = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get done => Completer<int>().future;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int columns) {}

  @override
  void close() {
    unawaited(_output.close());
  }
}

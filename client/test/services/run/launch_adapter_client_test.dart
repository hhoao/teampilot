import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';
import 'package:teampilot/services/run/launch_adapter_client.dart';
import 'package:teampilot/services/run/launch_adapter_protocol.dart';

String get _fakeAdapterScript {
  final testDir = Directory.current.path.endsWith('client')
      ? Directory.current.path
      : '${Directory.current.path}/client';
  return '$testDir/test/fixtures/fake_launch_adapter/fake_launch_adapter.dart';
}

Future<LaunchAdapterProcess> startFakeAdapter({
  required String command,
  required List<String> args,
}) async {
  // Use the Dart SDK binary — Platform.resolvedExecutable under flutter test
  // is flutter_tester and prints VM-service noise on stdout.
  final process = await Process.start(
    'dart',
    ['--disable-dart-dev', _fakeAdapterScript],
  );
  return LaunchAdapterProcess.fromIo(
    stdin: process.stdin,
    stdout: process.stdout,
    stderr: process.stderr,
    exitCode: process.exitCode,
    kill: process.kill,
  );
}

LaunchAdapterClient createClient() {
  return LaunchAdapterClient(
    startProcess: startFakeAdapter,
    extensionPathResolver: (_) => '/ext/fake',
  );
}

void main() {
  test('initialize launch output exited', () async {
    final client = createClient();
    addTearDown(client.dispose);

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
      lifecycle: LaunchAdapterLifecycle.sticky,
    );

    const sessionId = 's1';
    final outputFuture = client.outputStream
        .where((e) => e.sessionId == sessionId)
        .timeout(const Duration(seconds: 5))
        .first;

    await client.launch(
      sessionId: sessionId,
      configuration: {
        'id': 'main',
        'name': 'Main',
        'type': 'flutter',
        'request': 'launch',
      },
    );

    final output = await outputFuture;
    expect(output.data, contains('ok'));

    final exited = await client.waitExited(sessionId).timeout(
      const Duration(seconds: 5),
    );
    expect(exited.exitCode, 0);
  });

  test('configureAction returns configuration draft', () async {
    final client = createClient();
    addTearDown(client.dispose);

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
    );

    final draft = await client.configureAction(
      actionId: 'select_entry',
      workspaceFolder: '/proj',
      result: {'kind': 'file', 'path': '/proj/lib/main.dart'},
    );
    expect(draft.cancelled, isFalse);
    expect(draft.configuration?['id'], isNotEmpty);
  });

  test('provideOptions and optionsChanged', () async {
    final client = createClient();
    addTearDown(client.dispose);

    final optionsChangedFuture = client.optionsChanged
        .timeout(const Duration(seconds: 5))
        .first;

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
    );

    final pushed = await optionsChangedFuture;
    expect(pushed, isNotEmpty);
    expect(pushed.single.id, 'device');

    final options = await client.provideOptions(
      configurationId: 'main',
      configuration: {'type': 'flutter'},
    );
    expect(options.single.id, 'device');
    expect(options.single.type, LaunchOptionType.choice);
  });

  test('configurationsChanged includes isAction', () async {
    final client = createClient();
    addTearDown(client.dispose);

    final entriesFuture = client.configurationsChanged
        .timeout(const Duration(seconds: 5))
        .first;

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
    );

    final entries = await entriesFuture;
    expect(entries.any((e) => e.isAction == true), isTrue);
  });
}

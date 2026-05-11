import 'dart:convert';
import 'dart:io';

import 'package:flashskyai_client/services/temp_team_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory cliTeamsDir;
  late File registry;

  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('temp_cleaner_');
    cliTeamsDir = await Directory(p.join(tmp.path, 'teams')).create();
    registry = File(p.join(tmp.path, 'ui-temp-teams.json'));
  });

  tearDown(() async {
    if (await cliTeamsDir.parent.exists()) {
      await cliTeamsDir.parent.delete(recursive: true);
    }
  });

  TempTeamCleaner build() => TempTeamCleaner(
        registryPath: registry.path,
        cliTeamsDir: cliTeamsDir.path,
      );

  test('record persists names to disk', () async {
    final cleaner = build();
    await cleaner.record('demo-1');
    await cleaner.record('demo-2');

    expect(await registry.exists(), isTrue);
    final stored = (jsonDecode(await registry.readAsString()) as List)
        .cast<String>()
        .toSet();
    expect(stored, {'demo-1', 'demo-2'});
  });

  test('record ignores empty names', () async {
    final cleaner = build();
    await cleaner.record('  ');

    expect(await registry.exists(), isFalse);
  });

  test('cleanup deletes recorded folders and clears the registry', () async {
    await Directory(p.join(cliTeamsDir.path, 'demo-1')).create();
    await Directory(p.join(cliTeamsDir.path, 'demo-2')).create();
    await Directory(p.join(cliTeamsDir.path, 'keep')).create();

    final cleaner = build();
    await cleaner.record('demo-1');
    await cleaner.record('demo-2');
    await cleaner.cleanup();

    expect(await Directory(p.join(cliTeamsDir.path, 'demo-1')).exists(),
        isFalse);
    expect(await Directory(p.join(cliTeamsDir.path, 'demo-2')).exists(),
        isFalse);
    expect(
        await Directory(p.join(cliTeamsDir.path, 'keep')).exists(), isTrue);
    expect(await registry.exists(), isFalse);
  });

  test('cleanup tolerates missing folders', () async {
    final cleaner = build();
    await cleaner.record('ghost');

    await cleaner.cleanup();

    expect(await registry.exists(), isFalse);
  });

  test('cleanup with no registry is a no-op', () async {
    final cleaner = build();
    await cleaner.cleanup();
    // No throw, registry stays absent.
    expect(await registry.exists(), isFalse);
  });

  test('a fresh cleaner instance picks up the previous run registry',
      () async {
    await Directory(p.join(cliTeamsDir.path, 'crashed-1')).create();
    final first = build();
    await first.record('crashed-1');

    // Simulate a new process start with a brand new instance.
    final next = build();
    await next.cleanup();

    expect(await Directory(p.join(cliTeamsDir.path, 'crashed-1')).exists(),
        isFalse);
    expect(await registry.exists(), isFalse);
  });
}

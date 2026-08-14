import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
  });

  const definition = HookDefinition(
    id: 'h1',
    name: 'On start',
    event: HookEvent.sessionStart,
    action: CommandHookAction.raw('echo start'),
  );

  test('loadAll returns empty when library missing', () async {
    expect(await repository.loadAll(), isEmpty);
  });

  test('save then load round-trips', () async {
    await repository.save(definition);
    final loaded = await repository.load('h1');
    expect(loaded, definition);
    final all = await repository.loadAll();
    expect(all.map((d) => d.id), ['h1']);
  });

  test('load skips corrupt definitions', () async {
    await fs.writeString('/root/hooks/bad/hook.json', 'not json');
    await repository.save(definition);
    final all = await repository.loadAll();
    expect(all.map((d) => d.id), ['h1']);
  });

  test('delete removes directory', () async {
    await repository.save(definition);
    await repository.writeScript('h1', 'hook.sh', '#!/usr/bin/env bash\n');
    await repository.delete('h1');
    expect(await repository.load('h1'), isNull);
    expect(await repository.scriptFileNames('h1'), isEmpty);
  });

  test('scripts round-trip', () async {
    await repository.save(definition);
    await repository.writeScript('h1', 'hook.sh', 'echo hi');
    expect(await repository.readScript('h1', 'hook.sh'), 'echo hi');
    expect(await repository.scriptFileNames('h1'), ['hook.sh']);
  });
}

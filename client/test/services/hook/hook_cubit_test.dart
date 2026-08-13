import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;
  late HookCubit cubit;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
    cubit = HookCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  test('load populates definitions sorted', () async {
    await repository.save(const HookDefinition(
      id: 'h2',
      name: 'b',
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo b'),
    ));
    await repository.save(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo a'),
    ));
    await cubit.load();
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.definitions.map((d) => d.id), ['h1', 'h2']);
  });

  test('upsert writes definition and scripts; remove deletes', () async {
    final ok = await cubit.upsert(
      const HookDefinition(
        id: 'h1',
        name: 'a',
        event: HookEvent.stop,
        action: CommandHookAction.script(fileName: 'hook.sh'),
      ),
      scripts: const {'hook.sh': 'echo hi'},
    );
    expect(ok, isTrue);
    expect(await repository.readScript('h1', 'hook.sh'), 'echo hi');
    final removed = await cubit.remove('h1');
    expect(removed, isTrue);
    expect(await repository.load('h1'), isNull);
  });
}

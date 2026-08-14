import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/hook/import/hook_import_service.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;
  late HookImportService service;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
    service = HookImportService(repository: repository);
  });

  test('import saves definitions and scripts', () async {
    final count = await service.import([
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-abc',
          name: 'preToolUse',
          event: HookEvent.preToolUse,
          action: CommandHookAction.raw('bash /root/hooks/import-abc/x.sh'),
        ),
        scriptFileName: 'x.sh',
        scriptContent: 'exit 2',
      ),
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-def',
          name: 'stop',
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo done'),
        ),
      ),
    ]);
    expect(count, 2);
    expect(await repository.load('import-abc'), isNotNull);
    expect(await repository.readScript('import-abc', 'x.sh'), 'exit 2');
    expect(await repository.load('import-def'), isNotNull);
  });

  test('re-import with same id overwrites (idempotent upsert)', () async {
    await service.import([
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-abc',
          name: 'v1',
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo one'),
        ),
      ),
    ]);
    await service.import([
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-abc',
          name: 'v2',
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo two'),
        ),
      ),
    ]);
    final all = await repository.loadAll();
    expect(all, hasLength(1));
    expect(all.single.name, 'v2');
  });
}

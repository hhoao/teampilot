import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_library_resolver.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookLibraryResolver resolver;

  setUp(() {
    fs = InMemoryFilesystem();
    resolver = HookLibraryResolver(fs: fs, teampilotRoot: '/root');
  });

  Future<void> writeDefinition(HookDefinition definition) async {
    final repo = HookRepository(fs: fs, teampilotRoot: '/root');
    await repo.save(definition);
  }

  test('resolves raw command hooks in order with dedupe', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo a'),
    ));
    await writeDefinition(const HookDefinition(
      id: 'h2',
      name: 'b',
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo b'),
    ));
    final resolved = await resolver.resolve(['h2', 'h1', 'h2']);
    expect(resolved.warnings, isEmpty);
    expect(resolved.entries.map((e) => e.id), ['h2', 'h1']);
    expect(resolved.entries.first.source, HookSource.userLibrary);
    expect(resolved.entries.first.event, HookEvent.sessionStart);
  });

  test('loads managed script content', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.preToolUse,
      action: CommandHookAction.script(fileName: 'hook.sh'),
    ));
    await fs.writeString('/root/hooks/h1/hook.sh', '#!/usr/bin/env bash\necho hi');
    final resolved = await resolver.resolve(['h1']);
    final action = resolved.entries.single.action as CommandHookAction;
    expect(action.scriptContent, contains('echo hi'));
  });

  test('missing definition and missing script produce warnings', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.stop,
      action: CommandHookAction.script(fileName: 'hook.sh'),
    ));
    final resolved = await resolver.resolve(['missing', 'h1']);
    expect(resolved.entries, isEmpty);
    expect(
      resolved.warnings,
      containsAll(['hook_missing_missing', 'hook_script_missing_h1_hook.sh']),
    );
  });

  test('policy and env are carried over', () async {
    await writeDefinition(const HookDefinition(
      id: 'h1',
      name: 'a',
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      policy: HookPolicy.deny,
      timeoutSec: 12,
      env: {'A': 'b'},
      action: CommandHookAction.raw('exit 2'),
    ));
    final resolved = await resolver.resolve(['h1']);
    final entry = resolved.entries.single;
    expect(entry.policy, HookPolicy.deny);
    expect(entry.matcher, 'Bash');
    expect(entry.timeout, const Duration(seconds: 12));
    expect(entry.env, {'A': 'b'});
  });
}

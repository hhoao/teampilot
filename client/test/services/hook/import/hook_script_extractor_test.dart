import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/hook_script_extractor.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  HookScriptExtractor extractor({String? home}) =>
      HookScriptExtractor(fs: fs, homeDir: home);

  test('interpreter prefix extracts script and reads content', () async {
    await fs.writeString('/x/guard.sh', '#!/usr/bin/env bash\nexit 2');
    final result = await extractor().extract('bash /x/guard.sh');
    expect(result, isA<ScriptCopy>());
    final copy = result as ScriptCopy;
    expect(copy.interpreter, 'bash');
    expect(copy.fileName, 'guard.sh');
    expect(copy.content, contains('exit 2'));
  });

  test('python3 with quoted path', () async {
    await fs.writeString('/a b/x.py', 'print(1)');
    final result = await extractor()
        .extract('python3 "/a b/x.py"');
    final copy = result as ScriptCopy;
    expect(copy.interpreter, 'python3');
    expect(copy.fileName, 'x.py');
    expect(copy.content, 'print(1)');
  });

  test('-c inline command stays raw', () async {
    final result = await extractor().extract('python3 -c "print(1)"');
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, isNull);
  });

  test('bare absolute path uses bash interpreter', () async {
    await fs.writeString('/x/run.sh', 'echo hi');
    final result = await extractor().extract('/x/run.sh');
    final copy = result as ScriptCopy;
    expect(copy.interpreter, 'bash');
    expect(copy.fileName, 'run.sh');
  });

  test('placeholder path degrades to raw with reason', () async {
    final result = await extractor()
        .extract('bash \${CLAUDE_PROJECT_DIR}/.claude/hooks/x.sh');
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, 'placeholder');
  });

  test('unreadable script degrades to raw with reason', () async {
    final result = await extractor().extract('bash /missing/x.sh');
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, 'unreadable');
  });

  test('inline shell command stays raw', () async {
    final result = await extractor().extract("echo hi >> /tmp/log");
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, isNull);
  });

  test('tilde expands via homeDir', () async {
    await fs.writeString('/home/u/x.sh', 'echo hi');
    final result = await extractor(home: '/home/u').extract('bash ~/x.sh');
    final copy = result as ScriptCopy;
    expect(copy.fileName, 'x.sh');
    expect(copy.content, 'echo hi');
  });

  test('tilde without homeDir degrades to raw', () async {
    final result = await extractor().extract('bash ~/x.sh');
    expect(result, isA<RawCommand>());
  });
}

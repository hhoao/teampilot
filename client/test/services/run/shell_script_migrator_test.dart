import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';
import 'package:teampilot/services/run/shell_script_migrator.dart';

void main() {
  group('ShellScriptMigrator.migrate', () {
    test('shell true maps to scriptText with joined command line', () {
      final migrated = ShellScriptMigrator.migrate({
        'id': 'dev',
        'name': 'Dev',
        'type': 'process',
        'command': 'npm',
        'args': ['run', 'dev'],
        'shell': true,
        'cwd': r'${workspaceFolder}',
        'env': {'NODE_ENV': 'development'},
      });

      expect(migrated['type'], 'shellScript');
      expect(migrated['execute'], 'scriptText');
      expect(migrated['scriptText'], 'npm run dev');
      expect(migrated['scriptOptions'], '');
      expect(migrated['interpreterOptions'], '');
      expect(migrated['executeInTerminal'], false);
      expect(migrated['allowMultipleInstances'], false);
      expect(migrated['activateToolWindow'], true);
      expect(migrated['focusToolWindow'], false);
      expect(migrated['cwd'], r'${workspaceFolder}');
      expect(migrated['env'], {'NODE_ENV': 'development'});
      expect(migrated.containsKey('command'), isFalse);
      expect(migrated.containsKey('args'), isFalse);
      expect(migrated.containsKey('shell'), isFalse);
      expect(
        migrated['interpreterPath'],
        ShellScriptLaunchSchema.defaultInterpreterPath(),
      );
    });

    test('flutter run style maps to quoted scriptText (branch 2)', () {
      final migrated = ShellScriptMigrator.migrate({
        'type': 'process',
        'command': 'flutter',
        'args': ['run'],
      });
      expect(migrated['type'], 'shellScript');
      expect(migrated['execute'], 'scriptText');
      expect(migrated['scriptText'], contains('flutter'));
      expect(migrated['scriptText'], "'flutter' 'run'");
      expect(migrated['executeInTerminal'], false);
      expect(migrated['activateToolWindow'], true);
      expect(migrated['interpreterPath'], isNotEmpty);
      expect(migrated.containsKey('command'), isFalse);
      expect(migrated.containsKey('args'), isFalse);
    });

    test('quotes argv tokens with embedded single quotes', () {
      final migrated = ShellScriptMigrator.migrate({
        'type': 'process',
        'command': "it's",
        'args': ['a', "test"],
      });
      expect(migrated['scriptText'], "'it'\\''s' 'a' 'test'");
    });

    test('non-process types unchanged', () {
      final input = <String, Object?>{
        'type': 'shellScript',
        'execute': 'scriptFile',
        'scriptPath': './a.sh',
        'command': 'should-stay',
      };
      final migrated = ShellScriptMigrator.migrate(input);
      expect(migrated['type'], 'shellScript');
      expect(migrated['execute'], 'scriptFile');
      expect(migrated['scriptPath'], './a.sh');
      expect(migrated['command'], 'should-stay');

      final adapter = ShellScriptMigrator.maybeMigrate({
        'type': 'extension.adapter',
        'command': 'keep',
      });
      expect(adapter['type'], 'extension.adapter');
      expect(adapter['command'], 'keep');
    });
  });

  group('LaunchConfiguration.fromJson', () {
    test('migrates process on parse', () {
      final config = LaunchConfiguration.fromJson({
        'id': 'npm-dev',
        'name': 'npm run dev',
        'type': 'process',
        'command': 'npm',
        'args': ['run', 'dev'],
        'shell': true,
      });
      expect(config.type, 'shellScript');
      expect(config.command, isNull);
      expect(config.args, isEmpty);
      expect(config.shell, isNull);
      expect(config.extras['scriptText'], 'npm run dev');
      expect(config.extras['executeInTerminal'], false);
      expect(config.toJson().containsKey('command'), isFalse);
      expect(config.toJson().containsKey('args'), isFalse);
      expect(config.toJson().containsKey('shell'), isFalse);
    });
  });

  group('migrateConfiguration', () {
    test('converts in-memory process configuration', () {
      const original = LaunchConfiguration(
        id: 'flutter',
        name: 'Flutter',
        type: 'process',
        command: 'flutter',
        args: ['run'],
      );
      final migrated = ShellScriptMigrator.migrateConfiguration(original);
      expect(migrated.type, 'shellScript');
      expect(migrated.extras['scriptText'], "'flutter' 'run'");
      expect(migrated.command, isNull);
    });
  });

  test('launch_config_store loads process json as shellScript', () async {
    final io = MemoryLaunchConfigIo();
    final store = LaunchConfigStore(io: io);
    const folder = WorkspaceFolder(path: '/proj');
    final path = LaunchConfigStore.launchConfigPath(folder);
    await io.writeString(
      path,
      jsonEncode({
        'version': 1,
        'configurations': [
          {
            'id': 'dev',
            'name': 'Dev',
            'type': 'process',
            'command': 'npm',
            'args': ['run', 'dev'],
            'shell': true,
          },
        ],
      }),
      targetId: folder.targetId,
    );

    final listed = await store.listConfigurations(folders: [folder]);
    expect(listed, hasLength(1));
    final config = listed.single.configuration;
    expect(config.type, 'shellScript');
    expect(config.extras['scriptText'], 'npm run dev');
    expect(config.extras['executeInTerminal'], false);
    expect(config.toJson().containsKey('command'), isFalse);

    await store.upsertConfiguration(folder: folder, configuration: config);
    final saved = jsonDecode(io.files[path]!) as Map<String, dynamic>;
    final savedConfig =
        (saved['configurations'] as List).single as Map<String, dynamic>;
    expect(savedConfig['type'], 'shellScript');
    expect(savedConfig.containsKey('command'), isFalse);
    expect(savedConfig.containsKey('args'), isFalse);
    expect(savedConfig.containsKey('shell'), isFalse);
    expect(savedConfig['scriptText'], 'npm run dev');
  });
}

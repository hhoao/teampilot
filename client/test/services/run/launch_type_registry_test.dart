import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';
import 'package:teampilot/services/run/launch_type_registry.dart';
import 'package:teampilot/services/run/process_launch_schema.dart';

LaunchTypeContribution _flutterContrib(String extensionId) {
  return LaunchTypeContribution(
    extensionId: extensionId,
    type: 'flutter',
    kinds: const ['run'],
    adapterCommand: r'${extensionPath}/bin/adapter',
    adapterRuntime: 'workspace',
    lifecycle: LaunchAdapterLifecycle.sticky,
    configurationSchema: const {
      'type': 'object',
      'required': ['device'],
      'properties': {
        'device': {'type': 'string'},
      },
    },
    discover: const {'enabled': true, 'globs': ['pubspec.yaml']},
  );
}

void main() {
  test('process type is always registered', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    final process = reg.get('process');
    expect(process, isNotNull);
    expect(process!.extensionId, isNull);
    expect(process.configurationSchema, isNotNull);
  });

  test('duplicate type from two extensions marks conflict', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    final contribFlutterA = _flutterContrib('ext.flutter.a');
    reg.registerExtension(contribFlutterA);
    final result = reg.registerExtension(_flutterContrib('ext.flutter.b'));
    expect(result.isConflict, isTrue);
    expect(reg.get('flutter')?.extensionId, contribFlutterA.extensionId);
  });

  test('isAvailable returns true for process, false for extension types', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    reg.registerExtension(_flutterContrib('ext.flutter'));
    expect(reg.isAvailable('process', targetId: 'local'), isTrue);
    expect(reg.isAvailable('flutter', targetId: 'local'), isFalse);
  });

  test('process schema requires command', () {
    final errors = ProcessLaunchSchema.validate({
      'id': 'x',
      'name': 'X',
      'type': 'process',
    });
    expect(errors, isNotEmpty);
    expect(errors.single, contains('command'));
  });

  test('process schema accepts command with optional fields', () {
    final errors = ProcessLaunchSchema.validate({
      'id': 'x',
      'name': 'X',
      'type': 'process',
      'command': 'npm',
      'args': ['run', 'dev'],
      'env': {'NODE_ENV': 'development'},
      'cwd': r'${workspaceFolder}',
      'shell': true,
    });
    expect(errors, isEmpty);
  });
}

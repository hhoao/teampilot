import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_type_registry.dart';
import 'package:teampilot/services/run/launch_type_registrar.dart';

ExtensionManifest _flutterExtension({
  String id = 'ext.flutter',
  bool includeLaunchType = true,
}) {
  return ExtensionManifest(
    id: id,
    name: 'Flutter',
    detect: const ExtensionDetectSpec(executable: 'flutter'),
    effects: [
      if (includeLaunchType)
        ExtensionEffect(
          kind: 'launch-type',
          config: {
            'kind': 'launch-type',
            'type': 'flutter',
            'kinds': ['run'],
            'adapter': {
              'command': r'${extensionPath}/bin/adapter',
              'lifecycle': 'sticky',
              'runtime': 'workspace',
            },
            'configurationSchema': {
              'type': 'object',
              'required': ['device'],
              'properties': {
                'device': {'type': 'string'},
              },
            },
          },
        ),
    ],
  );
}

void main() {
  test('registrar registers launch-type from enabled extension', () async {
    final reg = LaunchTypeRegistry.withBuiltIns();
    await LaunchTypeRegistrar(
      extensions: [_flutterExtension()],
      detector: (_) async => true,
      extensionPathFor: (_) => '/ext/flutter',
    ).rebuild(reg);

    expect(reg.get('flutter')?.extensionId, 'ext.flutter');
    expect(reg.isAvailable('flutter', targetId: WorkspaceFolder.localTargetId), isTrue);
  });

  test('rebuild clears previous extension types before re-registering', () async {
    final reg = LaunchTypeRegistry.withBuiltIns();
    final registrar = LaunchTypeRegistrar(
      extensions: [_flutterExtension(id: 'ext.flutter.a')],
      detector: (_) async => true,
      extensionPathFor: (_) => '/ext/a',
    );
    await registrar.rebuild(reg);
    expect(reg.get('flutter')?.extensionId, 'ext.flutter.a');

    await LaunchTypeRegistrar(
      extensions: [_flutterExtension(id: 'ext.flutter.b')],
      detector: (_) async => true,
      extensionPathFor: (_) => '/ext/b',
    ).rebuild(reg);

    expect(reg.get('flutter')?.extensionId, 'ext.flutter.b');
    expect(reg.get('process'), isNotNull);
  });

  test('failed detect leaves type unavailable on local', () async {
    final reg = LaunchTypeRegistry.withBuiltIns();
    await LaunchTypeRegistrar(
      extensions: [_flutterExtension()],
      detector: (_) async => false,
      extensionPathFor: (_) => '/ext/flutter',
    ).rebuild(reg);

    expect(reg.get('flutter')?.extensionId, 'ext.flutter');
    expect(reg.isAvailable('flutter', targetId: WorkspaceFolder.localTargetId), isFalse);
  });

  test('remote target is unavailable even when detect passed', () async {
    final reg = LaunchTypeRegistry.withBuiltIns();
    await LaunchTypeRegistrar(
      extensions: [_flutterExtension()],
      detector: (_) async => true,
      extensionPathFor: (_) => '/ext/flutter',
    ).rebuild(reg);

    expect(reg.isAvailable('flutter', targetId: 'ssh:box'), isFalse);
    expect(reg.isAvailable('process', targetId: 'ssh:box'), isTrue);
  });

  test('extensionPathFor is exposed for LaunchAdapterClient', () async {
    final registrar = LaunchTypeRegistrar(
      extensions: [_flutterExtension()],
      detector: (_) async => true,
      extensionPathFor: (id) => '/installed/$id',
    );
    expect(registrar.pathResolver('ext.flutter'), '/installed/ext.flutter');
  });

  test('conflicting extension does not override first winner availability', () async {
    final reg = LaunchTypeRegistry.withBuiltIns();
    await LaunchTypeRegistrar(
      extensions: [
        _flutterExtension(id: 'ext.flutter.a'),
        _flutterExtension(id: 'ext.flutter.b'),
      ],
      detector: (manifest) async => manifest.id == 'ext.flutter.a',
      extensionPathFor: (_) => '/ext',
    ).rebuild(reg);

    expect(reg.get('flutter')?.extensionId, 'ext.flutter.a');
    expect(reg.isAvailable('flutter', targetId: WorkspaceFolder.localTargetId), isTrue);
  });
}

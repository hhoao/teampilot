import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';

void main() {
  test('launch-type effect parses type, adapter, kinds, discover, schema', () {
    final effect = ExtensionEffect.fromJson({
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
      'discover': {'enabled': true, 'globs': ['pubspec.yaml']},
    });
    final c = LaunchTypeContribution.fromEffect(
      extensionId: 'ext.flutter',
      effect: effect,
    );
    expect(c?.type, 'flutter');
    expect(c?.adapterRuntime, 'workspace');
    expect(c?.lifecycle, LaunchAdapterLifecycle.sticky);
    expect(c?.configurationSchema, isNotNull);
    expect(c?.configurationSchema!['required'], ['device']);
    expect(c?.kinds, ['run']);
    expect(c?.adapterCommand, r'${extensionPath}/bin/adapter');
    expect(c?.discover?['enabled'], isTrue);
  });

  test('rejects adapter runtime other than workspace', () {
    final effect = ExtensionEffect.fromJson({
      'kind': 'launch-type',
      'type': 'flutter',
      'adapter': {
        'command': 'adapter',
        'lifecycle': 'sticky',
        'runtime': 'host',
      },
      'configurationSchema': {'type': 'object'},
    });
    expect(
      LaunchTypeContribution.fromEffect(
        extensionId: 'ext.flutter',
        effect: effect,
      ),
      isNull,
    );
  });

  test('ExtensionEffect launch-type getters read config fields', () {
    final effect = ExtensionEffect.fromJson({
      'kind': 'launch-type',
      'type': 'flutter',
      'kinds': ['run', 'debug'],
      'adapter': {
        'command': '/bin/adapter',
        'lifecycle': 'oneshot',
        'runtime': 'workspace',
      },
      'configurationSchema': {'type': 'object'},
      'discover': {'enabled': false},
    });
    expect(effect.launchType, 'flutter');
    expect(effect.launchKinds, ['run', 'debug']);
    expect(effect.launchAdapter?['command'], '/bin/adapter');
    expect(effect.launchConfigurationSchema?['type'], 'object');
    expect(effect.launchDiscover?['enabled'], isFalse);
  });
}

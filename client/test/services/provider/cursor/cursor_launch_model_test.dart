import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_launch_model.dart';

void main() {
  group('CursorLaunchModel.parse', () {
    test('maps cursor-grok-4.6-high to grok-4.6 with high effort', () {
      final parsed = CursorLaunchModel.parse('cursor-grok-4.6-high');
      expect(parsed, isNotNull);
      expect(parsed!.modelId, 'grok-4.6');
      expect(parsed.parameters, [
        {'id': 'effort', 'value': 'high'},
        {'id': 'fast', 'value': 'false'},
      ]);
    });

    test('maps cursor-grok-4.6-high-fast to grok-4.6 with fast true', () {
      final parsed = CursorLaunchModel.parse('  cursor-grok-4.6-high-fast  ');
      expect(parsed!.modelId, 'grok-4.6');
      expect(parsed.parameters, [
        {'id': 'effort', 'value': 'high'},
        {'id': 'fast', 'value': 'true'},
      ]);
    });

    test('keeps thinking in the native model id', () {
      final parsed = CursorLaunchModel.parse('claude-opus-5-thinking-high');
      expect(parsed!.modelId, 'claude-opus-5-thinking');
      expect(parsed.parameters.first, {'id': 'effort', 'value': 'high'});
    });

    test('passes through simple ids like auto and gpt-5.2', () {
      expect(CursorLaunchModel.parse('auto')!.modelId, 'auto');
      expect(CursorLaunchModel.parse('gpt-5.2')!.modelId, 'gpt-5.2');
      expect(CursorLaunchModel.parse('gpt-5.2')!.parameters, isEmpty);
    });

    test('returns null for blank picker ids', () {
      expect(CursorLaunchModel.parse(''), isNull);
      expect(CursorLaunchModel.parse('   '), isNull);
    });
  });

  group('CursorLaunchModel.applyToConfig', () {
    test('stamps native model and selectedModel without dropping caches', () {
      final config = <String, Object?>{
        'version': 1,
        'serverConfigCache': {'backendUrl': 'https://api2.cursor.sh'},
        'authInfo': {'userId': 'u1'},
      };

      final stamped = CursorLaunchModel.applyToConfig(
        config,
        'cursor-grok-4.6-high',
      );

      expect(stamped['serverConfigCache'], config['serverConfigCache']);
      expect(stamped['authInfo'], config['authInfo']);
      expect(stamped['hasChangedDefaultModel'], isTrue);
      expect((stamped['model'] as Map)['modelId'], 'grok-4.6');
      expect((stamped['selectedModel'] as Map)['modelId'], 'grok-4.6');
      expect((stamped['selectedModel'] as Map)['parameters'], [
        {'id': 'effort', 'value': 'high'},
        {'id': 'fast', 'value': 'false'},
      ]);
      expect((stamped['modelParameters'] as Map)['grok-4.6'], [
        {'id': 'effort', 'value': 'high'},
        {'id': 'fast', 'value': 'false'},
      ]);
    });

    test('always stamps selectedModel.parameters even when empty', () {
      final stamped = CursorLaunchModel.applyToConfig(
        <String, Object?>{'version': 1},
        'composer-2.5',
      );

      expect((stamped['model'] as Map)['modelId'], 'composer-2.5');
      expect(stamped['selectedModel'], {
        'modelId': 'composer-2.5',
        'parameters': <Map<String, String>>[],
      });
      expect(stamped['hasChangedDefaultModel'], isTrue);
      expect(stamped.containsKey('modelParameters'), isFalse);
    });

    test('leaves config unchanged for blank picker ids', () {
      final config = <String, Object?>{'version': 1};
      expect(CursorLaunchModel.applyToConfig(config, ''), config);
    });
  });
}

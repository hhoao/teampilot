import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_model_capability.dart';
import 'package:teampilot/widgets/app_provider/provider_models_editor.dart';

void main() {
  test('parse reads the background tier role and toJson omits standard role', () {
    final entries = ProviderModelsEditor.parse({
      'main': {'name': 'Main', 'model': 'main', 'enabled': true},
      'cheap': {
        'name': 'Cheap',
        'model': 'cheap',
        'enabled': true,
        'role': 'background',
      },
    });

    final main = entries.firstWhere((e) => e.id == 'main');
    final cheap = entries.firstWhere((e) => e.id == 'cheap');
    expect(main.tier, ProviderModelTier.standard);
    expect(cheap.tier, ProviderModelTier.background);

    // Standard role is not persisted; background is.
    expect(main.toJson().containsKey('role'), isFalse);
    expect(cheap.toJson()['role'], 'background');
  });

  test('parse reads name/model/enabled and preserves extra keys', () {
    final entries = ProviderModelsEditor.parse({
      'deepseek-chat': {
        'name': 'DeepSeek Chat',
        'model': 'deepseek-chat',
        'enabled': true,
        'provider': 'DeepSeek',
      },
    });

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.id, 'deepseek-chat');
    expect(entry.name, 'DeepSeek Chat');
    expect(entry.model, 'deepseek-chat');
    expect(entry.enabled, isTrue);
    expect(entry.raw['provider'], 'DeepSeek');

    // Round-trip keeps the extra key and the core fields.
    expect(entry.toJson(), {
      'provider': 'DeepSeek',
      'name': 'DeepSeek Chat',
      'model': 'deepseek-chat',
      'enabled': true,
    });
  });

  test('parse falls back to key when value is not a map', () {
    final entries = ProviderModelsEditor.parse({'gpt-5.4': 'gpt-5.4'});
    final entry = entries.single;
    expect(entry.id, 'gpt-5.4');
    expect(entry.name, 'gpt-5.4');
    expect(entry.model, 'gpt-5.4');
    expect(entry.enabled, isTrue);
  });

  test('parse returns empty for null models', () {
    expect(ProviderModelsEditor.parse(null), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/services/ai/ai_feature_setting_resolver.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  const providers = AppProviderState(
    providersByCli: {
      CliTool.claude: [
        AppProviderConfig(
          id: 'claude-official',
          cli: CliTool.claude,
          name: 'Official',
          defaultModel: 'sonnet',
        ),
        AppProviderConfig(
          id: 'custom',
          cli: CliTool.claude,
          name: 'Custom',
          defaultModel: 'opus',
        ),
      ],
    },
    selectedProviderIdByCli: {CliTool.claude: 'custom'},
  );

  test('fills provider and model from global default when unset', () {
    final resolved = resolveAiFeatureSetting(
      stored: null,
      appProviders: providers,
      registry: registry,
    );

    expect(resolved.cli, CliTool.claude);
    expect(resolved.providerId, 'custom');
    expect(resolved.model, 'opus');
  });

  test('keeps stored provider and model when valid', () {
    const stored = AiFeatureSetting(
      cli: CliTool.claude,
      providerId: 'claude-official',
      model: 'haiku',
    );
    final resolved = resolveAiFeatureSetting(
      stored: stored,
      appProviders: providers,
      registry: registry,
    );

    expect(resolved.providerId, 'claude-official');
    expect(resolved.model, 'haiku');
  });

  test('falls back when stored provider id is unknown', () {
    const stored = AiFeatureSetting(
      cli: CliTool.claude,
      providerId: 'missing',
      model: 'm',
    );
    final resolved = resolveAiFeatureSetting(
      stored: stored,
      appProviders: providers,
      registry: registry,
    );

    expect(resolved.providerId, 'custom');
    expect(resolved.model, 'm');
  });

  test('resolves from active preset when set', () {
    const presets = [
      CliPreset(
        id: 'p1',
        name: 'Fast',
        cli: CliTool.claude,
        provider: 'claude-official',
        model: 'haiku',
        effort: 'low',
        createdAt: 0,
        updatedAt: 0,
      ),
    ];
    const stored = AiFeatureSetting(
      activePresetId: 'p1',
      cli: CliTool.codex,
      providerId: 'ignored',
      model: 'ignored',
    );
    final resolved = resolveAiFeatureSetting(
      stored: stored,
      appProviders: providers,
      registry: registry,
      globalPresets: presets,
    );

    expect(resolved.cli, CliTool.claude);
    expect(resolved.providerId, 'claude-official');
    expect(resolved.model, 'haiku');
    expect(resolved.effort, 'low');
  });

  group('aiFeatureIsConfigured', () {
    test('false when nothing saved even if global defaults exist', () {
      expect(
        aiFeatureIsConfigured(
          stored: null,
          registry: registry,
          appProviders: providers,
        ),
        isFalse,
      );
    });

    test('true for saved custom provider and model', () {
      const stored = AiFeatureSetting(
        cli: CliTool.claude,
        providerId: 'claude-official',
        model: 'haiku',
      );
      expect(
        aiFeatureIsConfigured(
          stored: stored,
          registry: registry,
          appProviders: providers,
        ),
        isTrue,
      );
    });

    test('true for saved active preset', () {
      const presets = [
        CliPreset(
          id: 'p1',
          name: 'Fast',
          cli: CliTool.claude,
          provider: 'claude-official',
          model: 'haiku',
          createdAt: 0,
          updatedAt: 0,
        ),
      ];
      const stored = AiFeatureSetting(
        activePresetId: 'p1',
        cli: CliTool.claude,
        providerId: '',
        model: '',
      );
      expect(
        aiFeatureIsConfigured(
          stored: stored,
          registry: registry,
          appProviders: providers,
          globalPresets: presets,
        ),
        isTrue,
      );
    });

    test('false for custom without model when picker required', () {
      const stored = AiFeatureSetting(
        cli: CliTool.claude,
        providerId: 'claude-official',
        model: '',
      );
      expect(
        aiFeatureIsConfigured(
          stored: stored,
          registry: registry,
          appProviders: providers,
        ),
        isFalse,
      );
    });
  });
}

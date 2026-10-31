import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_model_catalog.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_model_namespace.dart';

const _goModels = ['hy4-preview', 'kimi-k3.1-pro', 'deepseek-v4.1-flash'];

AppProviderConfig _provider({String subscription = 'opencode-go'}) =>
    AppProviderConfig(
      id: 'opencode',
      cli: CliTool.opencode,
      name: 'OpenCode',
      config: {
        if (subscription.isNotEmpty) 'opencodeSubscription': subscription,
      },
    );

String _ns(AppProviderConfig provider, String model) =>
    OpencodeModelNamespace.forModel(
      provider: provider,
      modelId: model,
      subscriptionModels: _goModels,
    );

void main() {
  test('without a subscription every model stays on Zen', () {
    final provider = _provider(subscription: '');
    expect(_ns(provider, 'deepseek-v4.1-flash-free'), 'opencode');
    expect(_ns(provider, 'hy4-preview'), 'opencode');
  });

  test('a non-OpenCode provider keeps its own namespace', () {
    // Custom/third-party rows (e.g. an OpenAI-compatible proxy named
    // `team-openai`) must not be rewritten to the Zen namespace.
    final provider = AppProviderConfig(
      id: 'team-openai',
      cli: CliTool.opencode,
      name: 'Team OpenAI',
      config: const {},
    );
    expect(_ns(provider, 'gpt-test'), 'team-openai');
  });

  test('a model the subscription serves uses the subscription namespace', () {
    expect(_ns(_provider(), 'hy4-preview'), 'opencode-go');
    expect(_ns(_provider(), 'deepseek-v4.1-flash'), 'opencode-go');
  });

  test('a Zen-only model uses the Zen namespace', () {
    // The reported bug: this used to be written as
    // `model: "opencode-go/deepseek-v4.1-flash-free"`, which the Go endpoint
    // rejects with "Model is unavailable".
    expect(_ns(_provider(), 'deepseek-v4.1-flash-free'), 'opencode');
    expect(_ns(_provider(), 'glm-5-free'), 'opencode');
  });

  test('a model both layers serve resolves to the paid subscription', () {
    expect(
      OpencodeModelNamespace.forModel(
        provider: _provider(),
        modelId: 'deepseek-v4.1-flash',
        subscriptionModels: const ['deepseek-v4.1-flash', 'hy4-preview'],
      ),
      'opencode-go',
    );
  });

  test('a custom model id falls back to the free layer', () {
    expect(_ns(_provider(), 'my-company/internal-model'), 'opencode');
  });

  test('an empty model keeps the subscription namespace', () {
    expect(_ns(_provider(), ''), 'opencode-go');
  });

  test(
    'falls back to the static catalog when no subscription list is given',
    () {
      // Regression guard: `deepseek-v4.1-flash-free` must not be treated as a Go
      // model by the offline fallback either.
      expect(
        OpencodeModelNamespace.forModel(
          provider: _provider(),
          modelId: 'deepseek-v4.1-flash-free',
        ),
        'opencode',
      );
      expect(
        OpencodeModelNamespace.forModel(
          provider: _provider(),
          modelId: 'deepseek-v4.1-flash',
        ),
        'opencode-go',
      );
      expect(
        OpencodeModelCatalog.knownModelsForProvider('opencode-go'),
        isNot(contains('deepseek-v4.1-flash-free')),
      );
    },
  );

  test('catalogKey prefers the subscription when one is bound', () {
    expect(OpencodeModelNamespace.catalogKey(_provider()), 'opencode-go');
    expect(
      OpencodeModelNamespace.catalogKey(_provider(subscription: '')),
      'opencode',
    );
  });
}

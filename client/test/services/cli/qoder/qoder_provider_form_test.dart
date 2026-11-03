import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';

void main() {
  const capability = QoderProviderCapability();

  test('maps effort and context window into the provider config', () {
    final config = capability.buildConfig(
      const ProviderFormInput(
        baseUrl: '',
        defaultModel: '',
        apiKeyField: 'api_key',
        config: {'keep': true},
        extra: {'reasoningEffort': 'xhigh', 'contextWindow': '300000'},
      ),
    );

    expect(config['reasoningEffort'], 'xhigh');
    expect(config['contextWindow'], 300000);
    expect(config['keep'], isTrue);
  });

  test('drops an empty or invalid context window', () {
    for (final raw in ['', 'abc', '0', '-5']) {
      final config = capability.buildConfig(
        ProviderFormInput(
          baseUrl: '',
          defaultModel: '',
          apiKeyField: 'api_key',
          config: const {},
          extra: {'contextWindow': raw},
        ),
      );
      expect(config.containsKey('contextWindow'), isFalse, reason: raw);
    }
  });

  test('offers the CLI reasoning effort levels', () {
    final levels = capability.effortCandidates(model: 'qfmodel');

    expect(
      levels,
      containsAll([
        'auto',
        'none',
        'low',
        'medium',
        'high',
        'xhigh',
        'max',
        'ultracode',
      ]),
    );
    expect(capability.isApplicable(model: 'qfmodel'), isTrue);
    expect(capability.defaultEffort(model: 'qfmodel'), '');
  });
}

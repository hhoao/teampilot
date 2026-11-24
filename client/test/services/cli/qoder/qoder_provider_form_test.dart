import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';

void main() {
  const capability = QoderProviderCapability();

  test('maps effort into the provider config', () {
    final config = capability.buildConfig(
      const ProviderFormInput(
        baseUrl: '',
        defaultModel: '',
        apiKeyField: 'api_key',
        config: {'keep': true},
        extra: {'reasoningEffort': 'xhigh'},
      ),
    );

    expect(config['reasoningEffort'], 'xhigh');
    expect(config['keep'], isTrue);
  });

  test('preserves the legacy provider-wide context window', () {
    final config = capability.buildConfig(
      const ProviderFormInput(
        baseUrl: '',
        defaultModel: '',
        apiKeyField: 'api_key',
        config: {'contextWindow': 300000},
        extra: {},
      ),
    );

    expect(config['contextWindow'], 300000);
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

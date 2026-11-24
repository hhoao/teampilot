import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';

void main() {
  const provider = AppProviderConfig(
    id: 'p',
    cli: CliTool.qoder,
    name: 'P',
    defaultModel: 'glm-5.3',
    config: {
      'contextWindow': 300000,
      'models': {
        'glm-5.3': {
          'name': 'GLM',
          'model': 'glm-5.3',
          'enabled': true,
          'contextWindow': 200000,
        },
        'alias': {
          'name': 'Alias row',
          'model': 'served-model',
          'enabled': true,
          'contextWindow': 128000,
        },
      },
    },
  );

  test('matches the model row by entry id first', () {
    expect(
      resolveModelContextWindow(provider, model: 'glm-5.3', entryId: 'glm-5.3'),
      200000,
    );
  });

  test('matches the served model when the row id differs', () {
    expect(resolveModelContextWindow(provider, model: 'served-model'), 128000);
  });

  test('returns null when no row declares a window', () {
    expect(resolveModelContextWindow(provider, model: 'unknown'), isNull);
  });

  test('ignores non-positive values', () {
    const invalid = AppProviderConfig(
      id: 'p',
      cli: CliTool.qoder,
      name: 'P',
      config: {
        'models': {
          'm': {'model': 'm', 'contextWindow': 0},
          'n': {'model': 'n', 'contextWindow': -5},
        },
      },
    );
    expect(resolveModelContextWindow(invalid, model: 'm'), isNull);
    expect(resolveModelContextWindow(invalid, model: 'n'), isNull);
  });

  test('uses the legacy provider-wide value only when opted in', () {
    expect(resolveModelContextWindow(provider, model: 'unknown'), isNull);
    expect(
      resolveModelContextWindow(
        provider,
        model: 'unknown',
        legacyProviderFallback: true,
      ),
      300000,
    );
  });
}

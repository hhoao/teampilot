import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('flashskyai stamps the provider id into every model entry', () {
    final cap = registry.capability<ProviderCapability>(CliTool.flashskyai)!;
    final normalized = cap.normalizeConfig(
      providerId: 'p1',
      config: {
        'models': {
          'm1': {'name': 'm1', 'provider': 'old'},
          'm2': 'raw',
        },
      },
    );
    expect(normalized['models'], {
      'm1': {'name': 'm1', 'provider': 'p1'},
      'm2': 'raw',
    });
  });

  test('other CLIs leave config untouched', () {
    for (final cli in CliTool.values) {
      if (cli == CliTool.flashskyai) continue;
      final cap = registry.capability<ProviderCapability>(cli)!;
      const config = {'a': 1};
      expect(
        identical(cap.normalizeConfig(providerId: 'p', config: config), config),
        isTrue,
        reason: '$cli',
      );
    }
  });

  test('FlashskyaiProviderCapability keeps the same behavior', () {
    const cap = FlashskyaiProviderCapability();
    expect(
      cap.normalizeConfig(
        providerId: 'x',
        config: {
          'models': {
            'm': {'provider': 'old'},
          },
        },
      ),
      {
        'models': {
          'm': {'provider': 'x'},
        },
      },
    );
    expect(cap.normalizeConfig(providerId: 'x', config: const {}), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/app_provider/provider_icon_catalog.g.dart';
import 'package:teampilot/widgets/app_provider/provider_icon_registry.dart';

void main() {
  test('normalizeProviderIconKey maps CodePilot aliases', () {
    expect(normalizeProviderIconKey('moonshot'), 'kimi');
    expect(normalizeProviderIconKey('volcengine'), 'huoshan');
    expect(normalizeProviderIconKey('xiaomi-mimo'), 'xiaomimimo');
    expect(normalizeProviderIconKey('bedrock'), 'aws');
  });

  test('providerIconAssetPath resolves bundled SVG presets', () {
    expect(providerIconAssetPath('anthropic'), endsWith('.svg'));
    expect(providerIconAssetPath('huoshan'), isNotNull);
    expect(
      providerIconAssetPaths.values.every((p) => p.endsWith('.svg')),
      isTrue,
    );
  });
}

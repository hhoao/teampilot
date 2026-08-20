import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_brand_icon.dart';

ManagedProvider _provider({
  String adapterId = 'fake',
  String name = 'Example',
  String url = 'https://example.test/usage',
}) => ManagedProvider(
  id: 'p1',
  name: name,
  kind: ManagedProviderKind.apiBalance,
  adapterId: adapterId,
  endpointConfig: ManagedProviderEndpointConfig(url: url),
);

void main() {
  test('official Codex uses bundled openai', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          adapterId: 'official-codex-subscription',
          name: 'Codex',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('openai'),
    );
  });

  test('official Claude uses bundled claude', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          adapterId: 'official-claude-subscription',
          name: 'Claude Code',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('claude'),
    );
  });

  test('DeepSeek host or name uses bundled deepseek', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          adapterId: 'http-json',
          name: 'Other',
          url: 'https://api.deepseek.com/user/balance',
        ),
      ),
      const ManagedProviderBrandIconSpec.bundled('deepseek'),
    );
    expect(
      resolveManagedProviderBrandIcon(
        _provider(adapterId: 'http-json', name: 'DeepSeek'),
      ),
      const ManagedProviderBrandIconSpec.bundled('deepseek'),
    );
  });

  test('https brand.iconUrl wins after adapter maps', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider().copyWith(
          brand: ManagedProviderBrand(iconUrl: 'https://cdn.example/icon.png'),
        ),
      ),
      const ManagedProviderBrandIconSpec.remote('https://cdn.example/icon.png'),
    );
  });

  test('unknown adapter falls back to initials', () {
    expect(
      resolveManagedProviderBrandIcon(_provider(name: 'Acme')),
      const ManagedProviderBrandIconSpec.initials('Acme'),
    );
  });
}

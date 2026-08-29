import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_brand_icon.dart';

ManagedProvider _provider({
  String adapterId = 'http-json',
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
  test('Codex host uses bundled openai', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          name: 'Codex',
          url: 'https://chatgpt.com/backend-api/wham/usage',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('openai'),
    );
  });

  test('Claude host uses bundled claude', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          name: 'Claude Code',
          url: 'https://api.anthropic.com/api/oauth/usage',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('claude'),
    );
  });

  test('Cursor host uses bundled cursor', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          name: 'Cursor',
          url: 'https://cursor.com/api/usage-summary',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('cursor'),
    );
  });

  test('DeepSeek host or name uses bundled deepseek', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          name: 'Other',
          url: 'https://api.deepseek.com/user/balance',
        ),
      ),
      const ManagedProviderBrandIconSpec.bundled('deepseek'),
    );
    expect(
      resolveManagedProviderBrandIcon(
        _provider(name: 'DeepSeek'),
      ),
      const ManagedProviderBrandIconSpec.bundled('deepseek'),
    );
  });

  test('https brand.iconUrl wins after host maps', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider().copyWith(
          brand: ManagedProviderBrand(iconUrl: 'https://cdn.example/icon.png'),
        ),
      ),
      const ManagedProviderBrandIconSpec.remote('https://cdn.example/icon.png'),
    );
  });

  test('unknown host falls back to initials', () {
    expect(
      resolveManagedProviderBrandIcon(_provider(name: 'Acme')),
      const ManagedProviderBrandIconSpec.initials('Acme'),
    );
  });
}

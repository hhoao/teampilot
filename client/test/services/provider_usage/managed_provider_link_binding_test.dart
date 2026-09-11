import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_binding.dart';

void main() {
  test('parses canonical provider source', () {
    final parsed = managedProviderLinkSourceOf('provider:claude:deepseek');
    expect(parsed, isNotNull);
    expect(parsed!.cli, CliTool.claude);
    expect(parsed.providerId, 'deepseek');
    expect(parsed.value, 'provider:claude:deepseek');
  });

  test('round-trips through formatter', () {
    final value = managedProviderLinkSourceValue(CliTool.codex, 'a b');
    expect(managedProviderLinkSourceOf(value)!.value, value);
  });

  test('rejects secret, cli, and malformed sources', () {
    expect(managedProviderLinkSourceOf('secret'), isNull);
    expect(managedProviderLinkSourceOf('cli:cursor'), isNull);
    expect(managedProviderLinkSourceOf('provider:claude:'), isNull);
    expect(managedProviderLinkSourceOf('provider:claude'), isNull);
    expect(managedProviderLinkSourceOf('provider:'), isNull);
    expect(managedProviderLinkSourceOf(''), isNull);
  });

  test('detects linked provider on a ManagedProvider', () {
    ManagedProvider provider(String source) => ManagedProvider(
      id: 'p',
      name: 'P',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(credentialSource: source),
    );
    expect(
      isManagedProviderLinkedToProvider(provider('provider:claude:d1')),
      isTrue,
    );
    expect(isManagedProviderLinkedToProvider(provider('secret')), isFalse);
  });
}

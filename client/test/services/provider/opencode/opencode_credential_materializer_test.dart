import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_credential_materializer.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';

void main() {
  test('opencode uses catalog apiKey instead of CLI login actions', () {
    final capability = OpencodeProviderCapability();
    const provider = AppProviderConfig(
      id: 'openai',
      cli: CliTool.opencode,
      name: 'OpenAI',
      category: AppProviderCategory.official,
      config: {'credentialKind': 'apiKey'},
    );

    expect(capability.appliesTo(provider), isFalse);
    expect(capability.hidesApiKeyFields(provider), isFalse);
    expect(capability.actionsFor(provider), isEmpty);
  });

  group('OpencodeCredentialMaterializer', () {
    test('isReady when apiKey is present', () {
      const provider = AppProviderConfig(
        id: 'openai',
        cli: CliTool.opencode,
        name: 'OpenAI',
        apiKey: 'sk-test',
        config: {'credentialKind': 'apiKey'},
      );
      expect(OpencodeCredentialMaterializer.isReady(provider), isTrue);
      expect(
        OpencodeCredentialMaterializer.authJsonContent(provider),
        contains('sk-test'),
      );
    });

    test('catalogFieldsFromAuthEntry maps api entries to apiKey', () {
      final fields = OpencodeCredentialMaterializer.catalogFieldsFromAuthEntry(
        providerId: 'openai',
        entry: {'type': 'api', 'key': 'sk-live'},
        existingConfig: const {},
      );
      expect(fields?.kind.name, 'apiKey');
      expect(fields?.apiKey, 'sk-live');
    });

    test('probe reports missing without apiKey', () async {
      const provider = AppProviderConfig(
        id: 'openai',
        cli: CliTool.opencode,
        name: 'OpenAI',
        config: {'credentialKind': 'apiKey'},
      );
      final probe = OpencodeCredentialMaterializer.probe(provider);
      expect(probe.isReady, isFalse);
      expect(
        (await OpencodeProviderCapability().probe(provider)).isReady,
        isFalse,
      );
    });
  });
}

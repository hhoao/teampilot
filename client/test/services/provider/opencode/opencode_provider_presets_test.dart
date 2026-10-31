import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/opencode_config.dart';
import 'package:teampilot/services/cli/opencode/opencode_go_layer.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_credential_kind.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_model_namespace.dart';
import 'package:teampilot/services/cli/opencode/provider_presets.dart';

AppProviderConfig _bound(AppProviderConfig provider) => provider.copyWith(
  apiKey: 'oc_sk_paid',
  config: {
    ...provider.config,
    OpencodeProviderConfigKeys.subscription: OpencodeGoLayer.namespace,
  },
);

void main() {
  test('opencode ships exactly one official catalog row', () {
    final official = OpencodeProviderPresets.all
        .where((preset) => preset.id == 'opencode')
        .toList();
    expect(official, hasLength(1));

    final preset = OpencodeProviderPresets.byId('opencode')!;
    expect(preset.label, 'OpenCode (official)');
    expect(preset.template.category, AppProviderCategory.official);
    expect(preset.template.isOfficial, isTrue);
    // The free Zen layer needs no credential, so a fresh row is usable at once.
    expect(preset.template.config['credentialKind'], 'none');
    expect(preset.template.defaultModel, 'deepseek-v4.1-flash-free');
  });

  test('the Go plan is one binding on that row, not a second row', () {
    final zen = OpencodeProviderPresets.byId('opencode')!.template;
    final go = _bound(zen);

    expect(go.id, 'opencode');
    expect(opencodeSubscriptionKey(go), OpencodeGoLayer.namespace);
    expect(
      OpencodeCredentialKindResolver.forProvider(go),
      OpencodeCredentialKind.apiKey,
    );
  });

  test('the Go binding writes its own endpoint and package', () {
    final bound = _bound(OpencodeProviderPresets.byId('opencode')!.template);

    final config = mergeOpencodeProvider(const <String, Object?>{}, bound);

    final entry =
        (config['providers'] as Map)['opencode-go'] as Map<String, Object?>;
    final settings = entry['settings'] as Map<String, Object?>;
    expect(settings['baseURL'], OpencodeGoLayer.baseUrl);
    expect(settings['apiKey'], 'oc_sk_paid');
    expect(entry['package'], 'aisdk:${OpencodeGoLayer.npm}');
    // The merged row itself must not be declared: Zen is built into the CLI.
    expect((config['providers'] as Map).containsKey('opencode'), isFalse);
  });

  test('the same row resolves each model to the namespace serving it', () {
    final bound = _bound(OpencodeProviderPresets.byId('opencode')!.template);

    expect(
      OpencodeModelNamespace.forModel(
        provider: bound,
        modelId: 'deepseek-v4.1-flash-free',
        subscriptionModels: const ['deepseek-v4.1-flash'],
      ),
      OpencodeModelNamespace.zen,
    );
    expect(
      OpencodeModelNamespace.forModel(
        provider: bound,
        modelId: 'deepseek-v4.1-flash',
        subscriptionModels: const ['deepseek-v4.1-flash'],
      ),
      OpencodeGoLayer.namespace,
    );
  });

  test('legacy opencode-go rows resolve to the merged preset', () {
    expect(OpencodeProviderPresets.byId('opencode-go'), isNotNull);
    expect(OpencodeProviderPresets.byId('opencode-go')!.id, 'opencode');
  });

  test('a fresh OpenCode row requires no credential until a key is added', () {
    final zen = OpencodeProviderPresets.byId('opencode')!.template;
    expect(
      OpencodeCredentialKindResolver.forProvider(zen),
      OpencodeCredentialKind.none,
    );
    expect(
      OpencodeCredentialKindResolver.forProvider(zen.copyWith(apiKey: 'oc_sk')),
      OpencodeCredentialKind.apiKey,
    );
  });
}

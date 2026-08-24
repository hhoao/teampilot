import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/claude/provider/claude_official_provider.dart';
import 'package:teampilot/services/cli/claude/capabilities/provider.dart';
import 'package:teampilot/services/cli/codex/provider/codex_official_provider.dart';
import 'package:teampilot/services/cli/codex/capabilities/provider.dart';
import 'package:teampilot/services/cli/cursor/capabilities/provider.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';

void main() {
  test('claude official provider exposes login and import actions', () {
    final capability = ClaudeProviderCapability();
    const provider = AppProviderConfig(
      id: 'anthropic',
      cli: CliTool.claude,
      name: 'Anthropic',
      category: AppProviderCategory.official,
      isOfficial: true,
      config: {'env': {}},
    );

    expect(isOfficialClaudeProvider(provider), isTrue);
    expect(capability.appliesTo(provider), isTrue);
    final actions = capability.actionsFor(provider);
    expect(
      actions.map((a) => a.kind),
      contains(ProviderCredentialActionKind.login),
    );
    expect(
      actions
          .where((a) => a.kind == ProviderCredentialActionKind.revoke)
          .single
          .showWhenReady,
      isTrue,
    );
    expect(capability.hidesApiKeyFields(provider), isTrue);
  });

  test('cursor official provider exposes login and import actions', () {
    final capability = CursorProviderCapability();
    const provider = AppProviderConfig(
      id: 'cursor-account',
      cli: CliTool.cursor,
      name: 'Cursor Account',
      category: AppProviderCategory.official,
      isOfficial: true,
    );

    expect(capability.appliesTo(provider), isTrue);
    expect(
      capability.actionsFor(provider).map((a) => a.kind),
      contains(ProviderCredentialActionKind.importDirectory),
    );
    expect(capability.hidesApiKeyFields(provider), isTrue);
  });

  test('codex openai official exposes login and import actions', () {
    final capability = CodexProviderCapability();
    const provider = AppProviderConfig(
      id: 'openai-official',
      cli: CliTool.codex,
      name: 'OpenAI Official',
      category: AppProviderCategory.official,
      isOfficial: true,
    );

    expect(isOfficialCodexOAuthProvider(provider), isTrue);
    expect(capability.appliesTo(provider), isTrue);
    expect(
      capability.actionsFor(provider).map((a) => a.kind),
      contains(ProviderCredentialActionKind.login),
    );
    expect(capability.hidesApiKeyFields(provider), isTrue);
  });

  test('duplicate codex official rows keep login capability', () {
    final capability = CodexProviderCapability();
    const provider = AppProviderConfig(
      id: 'openai-official-2',
      cli: CliTool.codex,
      name: 'OpenAI Official',
      category: AppProviderCategory.official,
      isOfficial: true,
    );

    expect(isOfficialCodexOAuthProvider(provider), isTrue);
    expect(capability.appliesTo(provider), isTrue);
    expect(
      capability.actionsFor(provider).map((a) => a.kind),
      contains(ProviderCredentialActionKind.login),
    );
    expect(capability.hidesApiKeyFields(provider), isTrue);
  });

  test('azure codex preset (isOfficial but third-party) stays API-key', () {
    final capability = CodexProviderCapability();
    const provider = AppProviderConfig(
      id: 'azure-openai',
      cli: CliTool.codex,
      name: 'Azure OpenAI',
      category: AppProviderCategory.thirdParty,
      isOfficial: true,
    );

    expect(isOfficialCodexOAuthProvider(provider), isFalse);
    expect(capability.appliesTo(provider), isFalse);
    expect(capability.hidesApiKeyFields(provider), isFalse);
  });

  test('opencode official provider uses catalog apiKey credential model', () {
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
}

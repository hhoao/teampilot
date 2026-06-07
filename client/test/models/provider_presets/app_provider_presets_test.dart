import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/provider_presets/claude_provider_presets.dart';
import 'package:teampilot/models/provider_presets/codex_provider_presets.dart';
import 'package:teampilot/models/provider_presets/flashskyai_provider_presets.dart';
import 'package:teampilot/models/provider_presets/opencode_provider_presets.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/tool_config_generator.dart';

void main() {
  test('CCSwitch claude and codex preset counts are preserved', () {
    expect(ClaudeProviderPresets.all, hasLength(56));
    expect(CodexProviderPresets.all, hasLength(27));
  });

  test('flashskyai presets mirror llm_config provider shapes', () {
    expect(FlashskyaiProviderPresets.all, hasLength(9));

    final deepseek = FlashskyaiProviderPresets.byId('DeepSeek')!.template;
    expect(deepseek.config['type'], 'api');
    expect(deepseek.config['provider_type'], 'openai');
    expect(deepseek.baseUrl, 'https://api.deepseek.com');
    expect(deepseek.defaultModel, 'deepseek-chat');

    final claude = FlashskyaiProviderPresets.byId('Claude')!.template;
    expect(claude.config['type'], 'account');
    expect(claude.config['account'], ['~/.claude/.credentials.json']);

    final openRouter = CodexProviderPresets.byId('openrouter')!.template;
    expect(openRouter.baseUrl, 'https://openrouter.ai/api/v1');
    expect(openRouter.config['configToml'], contains('openrouter'));
  });

  test('flashskyai account preset writes account paths to llm config', () {
    const generator = ToolConfigGenerator();
    final claude = FlashskyaiProviderPresets.byId('Claude')!.template;
    final llm = generator.buildFlashskyaiLlmConfig(claude);
    final entry = llm.providers['Claude']!;
    expect(entry.type, 'account');
    expect(entry.accounts, ['~/.claude/.credentials.json']);
    expect(llm.models['Sonnet']?.provider, 'Claude');
  });

  test('opencode presets are opencode-scoped with slug-stable provider ids', () {
    expect(OpencodeProviderPresets.all, isNotEmpty);
    for (final preset in OpencodeProviderPresets.all) {
      final t = preset.template;
      expect(t.cli, CliTool.opencode, reason: preset.id);
      // The saved id (slug of name) must equal the preset id so it survives as
      // opencode's provider key for `--model <id>/<model>`.
      expect(
        AppProviderCubit.slugifyId(t.name),
        preset.id,
        reason: 'name "${t.name}" must slugify to id "${preset.id}"',
      );
    }
  });

  test('opencode custom template carries the openai-compatible npm hint', () {
    final custom = OpencodeProviderPresets.byId('openai-compatible')!.template;
    expect(custom.config['npm'], '@ai-sdk/openai-compatible');

    final deepseek = OpencodeProviderPresets.byId('deepseek')!.template;
    expect(deepseek.baseUrl, 'https://api.deepseek.com');
    expect(deepseek.config.containsKey('npm'), isFalse);
  });

  test('opencode zen preset ships a default model', () {
    final zen = OpencodeProviderPresets.byId('opencode')!.template;
    expect(zen.defaultModel, 'claude-sonnet-4-5');
  });

  test('codex preset TOML is valid', () {
    const generator = ToolConfigGenerator();
    for (final preset in CodexProviderPresets.all) {
      final toml = preset.template.config['configToml'] as String? ?? '';
      if (toml.trim().isEmpty) continue;
      expect(generator.validateCodexToml(toml), isNull, reason: preset.id);
    }
  });
}

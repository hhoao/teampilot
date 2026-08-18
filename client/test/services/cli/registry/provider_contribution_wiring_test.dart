import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';

void main() {
  test('provider set preserves definition order before injected providers', () {
    final registry = _registryWithCapabilities([
      const _PromptProvider('cli-a'),
      const _PromptProvider('cli-b'),
    ]);
    final set = ResourceProviderSet.fromRegistryAndInjected(
      cli: CliTool.claude,
      registry: registry,
      injected: ResourceProviderSet(
        prompts: [const _PromptProvider('runtime-a')],
      ),
    );

    expect(set.prompts.map((provider) => provider.providerId), [
      'cli-a',
      'cli-b',
      'runtime-a',
    ]);
  });

  test('provider set copies and freezes composed provider lists', () {
    final cliProviders = [const _PromptProvider('cli')];
    final injectedProviders = [const _PromptProvider('injected')];
    final registry = _registryWithCapabilities(cliProviders);
    final set = ResourceProviderSet.fromRegistryAndInjected(
      cli: CliTool.claude,
      registry: registry,
      injected: ResourceProviderSet(prompts: injectedProviders),
    );

    cliProviders.add(const _PromptProvider('late-cli'));
    injectedProviders.add(const _PromptProvider('late-injected'));

    expect(set.prompts.map((provider) => provider.providerId), [
      'cli',
      'injected',
    ]);
    expect(
      () => set.prompts.add(const _PromptProvider('mutation')),
      throwsUnsupportedError,
    );
  });

  test(
    'provider set rejects duplicate provider ids within one resource kind',
    () {
      final registry = _registryWithCapabilities([
        const _PromptProvider('duplicate'),
      ]);

      expect(
        () => ResourceProviderSet.fromRegistryAndInjected(
          cli: CliTool.claude,
          registry: registry,
          injected: ResourceProviderSet(
            prompts: [const _PromptProvider('duplicate')],
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('registry providersOf returns unconstrained matching capabilities', () {
    const prompt = _PromptProvider('prompt');
    const skill = _SkillProvider('skill');
    const mcp = _McpProvider('mcp');
    final registry = _registryWithCapabilities([prompt, skill, mcp]);

    expect(registry.providersOf<PromptContributionProvider>(CliTool.claude), [
      prompt,
    ]);
    expect(registry.providersOf<_SkillProvider>(CliTool.claude), [skill]);
    expect(registry.providersOf<_McpProvider>(CliTool.claude), [mcp]);
    expect(registry.providersOf<_HookProvider>(CliTool.claude), isEmpty);
  });
}

CliToolRegistry _registryWithCapabilities(List<CliCapability> capabilities) {
  return CliToolRegistry()..register(_FakeCliTool(capabilities));
}

final class _FakeCliTool implements CliToolDefinition {
  const _FakeCliTool(this.capabilities);

  @override
  final List<CliCapability> capabilities;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;
}

final class _PromptProvider
    implements CliCapability, PromptContributionProvider {
  const _PromptProvider(this.providerId);

  @override
  final String providerId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(
    PromptProviderContext context,
  ) => const [];
}

final class _SkillProvider implements CliCapability, SkillContributionProvider {
  const _SkillProvider(this.providerId);

  @override
  final String providerId;

  @override
  FutureOr<Iterable<SkillContribution>> provide(SkillProviderContext context) =>
      const [];
}

final class _McpProvider implements CliCapability, McpContributionProvider {
  const _McpProvider(this.providerId);

  @override
  final String providerId;

  @override
  FutureOr<Iterable<McpContribution>> provide(McpProviderContext context) =>
      const [];
}

final class _HookProvider implements CliCapability, HookContributionProvider {
  const _HookProvider(this.providerId);

  @override
  final String providerId;

  @override
  FutureOr<Iterable<HookContribution>> provide(HookProviderContext context) =>
      const [];
}

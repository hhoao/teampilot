import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
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

  test('public constructor copies and freezes every provider list', () {
    final prompts = [const _PromptProvider('prompt')];
    final skills = [const _SkillProvider('skill')];
    final mcp = [const _McpProvider('mcp')];
    final hooks = [const _HookProvider('hook')];
    final set = ResourceProviderSet(
      prompts: prompts,
      skills: skills,
      mcp: mcp,
      hooks: hooks,
    );

    prompts.add(const _PromptProvider('late-prompt'));
    skills.add(const _SkillProvider('late-skill'));
    mcp.add(const _McpProvider('late-mcp'));
    hooks.add(const _HookProvider('late-hook'));

    expect(set.prompts.map((provider) => provider.providerId), ['prompt']);
    expect(set.skills.map((provider) => provider.providerId), ['skill']);
    expect(set.mcp.map((provider) => provider.providerId), ['mcp']);
    expect(set.hooks.map((provider) => provider.providerId), ['hook']);
    expect(
      () => set.prompts.add(const _PromptProvider('mutation')),
      throwsUnsupportedError,
    );
    expect(
      () => set.skills.add(const _SkillProvider('mutation')),
      throwsUnsupportedError,
    );
    expect(
      () => set.mcp.add(const _McpProvider('mutation')),
      throwsUnsupportedError,
    );
    expect(
      () => set.hooks.add(const _HookProvider('mutation')),
      throwsUnsupportedError,
    );
  });

  test('public constructor rejects duplicate ids in every resource kind', () {
    expect(
      () => ResourceProviderSet(
        prompts: [
          const _PromptProvider('duplicate'),
          const _PromptProvider('duplicate'),
        ],
      ),
      throwsStateError,
    );
    expect(
      () => ResourceProviderSet(
        skills: [
          const _SkillProvider('duplicate'),
          const _SkillProvider('duplicate'),
        ],
      ),
      throwsStateError,
    );
    expect(
      () => ResourceProviderSet(
        mcp: [const _McpProvider('duplicate'), const _McpProvider('duplicate')],
      ),
      throwsStateError,
    );
    expect(
      () => ResourceProviderSet(
        hooks: [
          const _HookProvider('duplicate'),
          const _HookProvider('duplicate'),
        ],
      ),
      throwsStateError,
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

  test('resource contexts copy list and map inputs into immutable views', () {
    final additionalDirectories = ['/workspace'];
    final extraServers = <McpServerSpec>[];
    final credentials = <String, String>{'token': 'secret'};
    final endpoints = <String, String>{'managed': 'http://localhost'};

    final promptContext = PromptProviderContext(
      cli: CliTool.claude,
      additionalDirectories: additionalDirectories,
    );
    final mcpContext = McpProviderContext(
      cli: CliTool.claude,
      extraServers: extraServers,
      credentials: credentials,
    );
    final hookContext = HookProviderContext(
      cli: CliTool.claude,
      endpoints: endpoints,
    );

    additionalDirectories.add('/late');
    extraServers.add(const StdioMcpServer(name: 'late', command: 'server'));
    credentials['late'] = 'value';
    endpoints['late'] = 'value';

    expect(promptContext.additionalDirectories, ['/workspace']);
    expect(mcpContext.extraServers, isEmpty);
    expect(mcpContext.credentials, {'token': 'secret'});
    expect(hookContext.endpoints, {'managed': 'http://localhost'});
    expect(
      () => promptContext.additionalDirectories.add('/mutation'),
      throwsUnsupportedError,
    );
    expect(
      () => mcpContext.extraServers.add(
        const StdioMcpServer(name: 'mutation', command: 'server'),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => mcpContext.credentials['mutation'] = 'value',
      throwsUnsupportedError,
    );
    expect(
      () => hookContext.endpoints['mutation'] = 'value',
      throwsUnsupportedError,
    );
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

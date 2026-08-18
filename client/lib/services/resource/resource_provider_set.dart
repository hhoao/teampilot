import '../cli/registry/cli_tool_registry.dart';
import '../../models/team_config.dart';
import 'providers/hook_contribution_provider.dart';
import 'providers/mcp_contribution_provider.dart';
import 'providers/prompt_contribution_provider.dart';
import 'providers/skill_contribution_provider.dart';

/// Ordered providers grouped by resource kind.
class ResourceProviderSet {
  const ResourceProviderSet({
    this.prompts = const [],
    this.skills = const [],
    this.mcp = const [],
    this.hooks = const [],
  });

  ResourceProviderSet._composed({
    required this.prompts,
    required this.skills,
    required this.mcp,
    required this.hooks,
  });

  final List<PromptContributionProvider> prompts;
  final List<SkillContributionProvider> skills;
  final List<McpContributionProvider> mcp;
  final List<HookContributionProvider> hooks;

  /// Composes CLI-definition providers followed by explicitly injected ones.
  static ResourceProviderSet fromRegistryAndInjected({
    required CliTool cli,
    required CliToolRegistry registry,
    ResourceProviderSet injected = const ResourceProviderSet(),
  }) {
    return ResourceProviderSet._composed(
      prompts: _compose(
        registry.providersOf<PromptContributionProvider>(cli),
        injected.prompts,
        (provider) => provider.providerId,
        'prompts',
      ),
      skills: _compose(
        registry.providersOf<SkillContributionProvider>(cli),
        injected.skills,
        (provider) => provider.providerId,
        'skills',
      ),
      mcp: _compose(
        registry.providersOf<McpContributionProvider>(cli),
        injected.mcp,
        (provider) => provider.providerId,
        'mcp',
      ),
      hooks: _compose(
        registry.providersOf<HookContributionProvider>(cli),
        injected.hooks,
        (provider) => provider.providerId,
        'hooks',
      ),
    );
  }

  static List<T> _compose<T>(
    Iterable<T> registryProviders,
    Iterable<T> injectedProviders,
    String Function(T provider) providerId,
    String resourceKind,
  ) {
    final result = List<T>.unmodifiable([
      ...registryProviders,
      ...injectedProviders,
    ]);
    final seen = <String>{};
    for (final provider in result) {
      if (!seen.add(providerId(provider))) {
        throw StateError(
          'Duplicate $resourceKind contribution provider id: '
          '${providerId(provider)}',
        );
      }
    }
    return result;
  }
}

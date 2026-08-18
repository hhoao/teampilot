import '../cli/registry/cli_tool_registry.dart';
import '../../models/team_config.dart';
import 'providers/hook_contribution_provider.dart';
import 'providers/mcp_contribution_provider.dart';
import 'providers/prompt_contribution_provider.dart';
import 'providers/skill_contribution_provider.dart';

/// Ordered providers grouped by resource kind.
class ResourceProviderSet {
  ResourceProviderSet({
    Iterable<PromptContributionProvider> prompts = const [],
    Iterable<SkillContributionProvider> skills = const [],
    Iterable<McpContributionProvider> mcp = const [],
    Iterable<HookContributionProvider> hooks = const [],
  }) : prompts = _copyAndValidate(
         prompts,
         (provider) => provider.providerId,
         'prompts',
       ),
       skills = _copyAndValidate(
         skills,
         (provider) => provider.providerId,
         'skills',
       ),
       mcp = _copyAndValidate(mcp, (provider) => provider.providerId, 'mcp'),
       hooks = _copyAndValidate(
         hooks,
         (provider) => provider.providerId,
         'hooks',
       );

  const ResourceProviderSet._empty()
    : prompts = const [],
      skills = const [],
      mcp = const [],
      hooks = const [];

  static const empty = ResourceProviderSet._empty();

  final List<PromptContributionProvider> prompts;
  final List<SkillContributionProvider> skills;
  final List<McpContributionProvider> mcp;
  final List<HookContributionProvider> hooks;

  /// Composes CLI-definition providers followed by explicitly injected ones.
  static ResourceProviderSet fromRegistryAndInjected({
    required CliTool cli,
    required CliToolRegistry registry,
    ResourceProviderSet injected = empty,
  }) {
    return ResourceProviderSet(
      prompts: _compose(
        registry.providersOf<PromptContributionProvider>(cli),
        injected.prompts,
      ),
      skills: _compose(
        registry.providersOf<SkillContributionProvider>(cli),
        injected.skills,
      ),
      mcp: _compose(
        registry.providersOf<McpContributionProvider>(cli),
        injected.mcp,
      ),
      hooks: _compose(
        registry.providersOf<HookContributionProvider>(cli),
        injected.hooks,
      ),
    );
  }

  static List<T> _compose<T>(
    Iterable<T> registryProviders,
    Iterable<T> injectedProviders,
  ) {
    return [...registryProviders, ...injectedProviders];
  }

  static List<T> _copyAndValidate<T>(
    Iterable<T> providers,
    String Function(T provider) providerId,
    String resourceKind,
  ) {
    final result = List<T>.unmodifiable(providers);
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

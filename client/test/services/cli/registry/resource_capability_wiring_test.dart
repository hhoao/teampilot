import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';

void main() {
  test('every launchable CLI wires all resource target capabilities', () {
    final registry = CliToolRegistry.builtIn();

    for (final definition in registry.launchable) {
      final cli = definition.id;
      expect(
        registry.capability<PromptCapability>(cli),
        isNotNull,
        reason: '${cli.value} prompt target',
      );
      expect(
        registry.capability<SkillCapability>(cli),
        isNotNull,
        reason: '${cli.value} skill target',
      );
      expect(
        registry.capability<McpCapability>(cli),
        isNotNull,
        reason: '${cli.value} MCP target',
      );
      expect(
        registry.capability<HookCapability>(cli),
        isNotNull,
        reason: '${cli.value} hook target',
      );
    }
  });

  test(
    'real CLI registry exposes each built-in prompt as a source provider',
    () {
      final registry = CliToolRegistry.builtIn();

      for (final definition in registry.launchable) {
        final providers = registry
            .providersOf<PromptContributionProvider>(definition.id)
            .toList();
        expect(
          providers,
          hasLength(1),
          reason: '${definition.id.value} prompt provider count',
        );
        expect(providers.single.providerId, definition.id.value);
        expect(
          providers.single,
          same(registry.capability<PromptCapability>(definition.id)),
          reason: '${definition.id.value} target/provider capability identity',
        );
      }
    },
  );

  test(
    'provider lookup keeps dynamic resource providers out of CLI definitions',
    () {
      final registry = CliToolRegistry.builtIn();

      for (final definition in registry.launchable) {
        final set = ResourceProviderSet.fromRegistryAndInjected(
          cli: definition.id,
          registry: registry,
        );
        expect(set.prompts, hasLength(1), reason: definition.id.value);
        expect(
          registry.providersOf<SkillContributionProvider>(definition.id),
          isEmpty,
          reason: '${definition.id.value} dynamic skill providers',
        );
        expect(
          registry.providersOf<McpContributionProvider>(definition.id),
          isEmpty,
          reason: '${definition.id.value} dynamic MCP providers',
        );
        expect(
          registry.providersOf<HookContributionProvider>(definition.id),
          isEmpty,
          reason: '${definition.id.value} dynamic hook providers',
        );
      }
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_contribution.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  test(
    'all built-in launchable definitions register deterministic launch providers',
    () {
      final firstRegistry = _newBuiltInRegistry();
      final secondRegistry = _newBuiltInRegistry();

      final firstLaunchable = firstRegistry.launchable.toList();
      expect(
        firstLaunchable.map((definition) => definition.id),
        unorderedEquals(CliTool.values),
      );

      for (final definition in firstLaunchable) {
        final firstProviders = firstRegistry
            .capabilitiesOf<CliLaunchArgProvider>(definition.id)
            .toList();
        final secondProviders = secondRegistry
            .capabilitiesOf<CliLaunchArgProvider>(definition.id)
            .toList();

        expect(firstProviders, isNotEmpty, reason: definition.id.value);
        expect(
          _providerRegistrationKeys(firstProviders),
          _providerRegistrationKeys(
            definition.capabilities.whereType<CliLaunchArgProvider>(),
          ),
          reason: '${definition.id.value} is missing a registered provider',
        );
        expect(
          _providerRegistrationKeys(firstProviders),
          _providerRegistrationKeys(secondProviders),
          reason: definition.id.value,
        );

        final context = _contextFor(definition.id);
        final firstContributions = _contributions(firstProviders, context);
        final secondContributions = _contributions(secondProviders, context);

        expect(
          _contributionKeys(firstContributions),
          _contributionKeys(secondContributions),
          reason: definition.id.value,
        );
        expect(
          _contributionKeys(firstContributions).toSet(),
          hasLength(_contributionKeys(firstContributions).length),
          reason: '${definition.id.value} has duplicate contribution keys',
        );
      }
    },
  );
}

CliToolRegistry _newBuiltInRegistry() {
  final registry = CliToolRegistry();
  registerBuiltInCliTools(registry);
  return registry;
}

CliLaunchContext _contextFor(CliTool cli) {
  return CliLaunchContext(
    team: TeamProfile(
      id: 'launch-contract-team',
      name: 'launch-contract-team',
      cli: cli,
      teamMode: TeamMode.mixed,
      extraArgs: '--team-extra "team value"',
    ),
    member: const TeamMemberConfig(
      id: 'launch-contract-member',
      name: 'Launch Contract Member',
      provider: 'provider',
      model: 'model',
      agent: 'agent',
      extraArgs: '--member-extra "member value"',
      launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
    ),
    workingDirectory: '/workspace',
    additionalDirectories: const ['/workspace/shared-a', '/workspace/shared-b'],
    resumeSessionId: 'launch-contract-session',
    appendSystemPromptFile: '/workspace/prompt.md',
  );
}

List<String> _providerRegistrationKeys(
  Iterable<CliLaunchArgProvider> providers,
) {
  return [for (final provider in providers) provider.runtimeType.toString()];
}

List<CliLaunchArgContribution> _contributions(
  Iterable<CliLaunchArgProvider> providers,
  CliLaunchContext context,
) {
  return [
    for (final provider in providers) ...provider.buildLaunchArgs(context),
  ];
}

List<String> _contributionKeys(
  Iterable<CliLaunchArgContribution> contributions,
) {
  return [for (final contribution in contributions) contribution.key];
}

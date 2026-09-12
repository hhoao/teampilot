import '../../../../models/launch_security_policy.dart';
import '../../../../models/team_config.dart';
import '../capabilities/cli_launch_security_capability.dart';
import '../cli_capability.dart';
import 'cli_launch_context.dart';
import 'cli_headless_launch_arg_provider.dart';
import 'cli_headless_launch_context.dart';
import '../cli_tool_definition.dart';
import 'cli_launch_arg_contribution.dart';
import 'cli_launch_arg_provider.dart';
import 'cli_launch_capability_error.dart';
import 'cli_launch_constraint.dart';
import 'cli_headless_launch_constraint.dart';

/// Collects, validates, orders, and flattens launch argument contributions.
final class CliLaunchArgAssembler {
  const CliLaunchArgAssembler();

  List<String> assemble(CliToolDefinition tool, CliLaunchContext context) {
    _validateLaunchSecurityPolicy(tool, context.launchSecurityPolicy);
    return _assemble(
      cli: tool.id,
      capabilities: tool.capabilities,
      validate: (capability) {
        if (capability case final CliLaunchConstraint constraint) {
          constraint.validateLaunch(context);
        }
      },
      contributions: (capability) => capability is CliLaunchArgProvider
          ? capability.buildLaunchArgs(context)
          : const [],
    );
  }

  List<String> assembleHeadless(
    CliToolDefinition tool,
    CliHeadlessLaunchContext context,
  ) {
    _validateLaunchSecurityPolicy(tool, context.securityPolicy);
    return _assemble(
      cli: tool.id,
      capabilities: tool.capabilities,
      validate: (capability) {
        if (capability case final CliHeadlessLaunchConstraint constraint) {
          constraint.validateHeadlessLaunch(context);
        }
      },
      contributions: (capability) => capability is CliHeadlessLaunchArgProvider
          ? capability.buildHeadlessLaunchArgs(context)
          : const [],
    );
  }

  void _validateLaunchSecurityPolicy(
    CliToolDefinition tool,
    LaunchSecurityPolicy policy,
  ) {
    final capabilities = tool.capabilities
        .whereType<CliLaunchSecurityCapability>()
        .toList();
    if (capabilities.length != 1) {
      throw StateError(
        'CLI ${tool.id.value} must register exactly one '
        'CliLaunchSecurityCapability',
      );
    }

    final capability = capabilities.single;
    if (capability.supportedPolicies.contains(policy)) return;

    throw CliLaunchCapabilityException(
      cli: tool.id,
      contributionKey: 'launch-security-policy',
      reason:
          'CLI ${tool.id.value} supports launch security policies '
          '${capability.supportedPolicies.map(describeLaunchSecurityPolicy).join(', ')}, '
          'but received ${describeLaunchSecurityPolicy(policy)}.',
    );
  }

  List<String> _assemble({
    required CliTool cli,
    required Iterable<CliCapability> capabilities,
    required void Function(CliCapability) validate,
    required Iterable<CliLaunchArgContribution> Function(CliCapability)
    contributions,
  }) {
    final collected = <_CollectedContribution>[];
    final byKey = <String, CliLaunchArgContribution>{};
    final byExclusiveGroup = <String, CliLaunchArgContribution>{};

    var providerIndex = 0;
    for (final capability in capabilities) {
      validate(capability);

      var contributionIndex = 0;
      for (final contribution in contributions(capability)) {
        final previousKey = byKey[contribution.key];
        if (previousKey != null) {
          throw CliLaunchCapabilityException(
            cli: cli,
            contributionKey: contribution.key,
            reason:
                'Duplicate launch argument contribution key '
                "'${contribution.key}'.",
          );
        }
        byKey[contribution.key] = contribution;

        final group = contribution.exclusiveGroup;
        if (group != null) {
          final previousGroup = byExclusiveGroup[group];
          if (previousGroup != null) {
            throw CliLaunchCapabilityException(
              cli: cli,
              contributionKey: contribution.key,
              reason:
                  'Launch argument contributions '
                  "'${previousGroup.key}' and '${contribution.key}' "
                  "share exclusive group '$group'.",
              exclusiveGroup: group,
              conflictingContributionKey: previousGroup.key,
            );
          }
          byExclusiveGroup[group] = contribution;
        }

        collected.add(
          _CollectedContribution(
            contribution: contribution,
            providerIndex: providerIndex,
            contributionIndex: contributionIndex,
          ),
        );
        contributionIndex++;
      }
      if (capability is CliLaunchArgProvider ||
          capability is CliHeadlessLaunchArgProvider) {
        providerIndex++;
      }
    }

    collected.sort((left, right) {
      final byPhase = left.contribution.phase.index.compareTo(
        right.contribution.phase.index,
      );
      if (byPhase != 0) return byPhase;

      final byProvider = left.providerIndex.compareTo(right.providerIndex);
      if (byProvider != 0) return byProvider;

      return left.contributionIndex.compareTo(right.contributionIndex);
    });

    return [for (final item in collected) ...item.contribution.args];
  }
}

final class _CollectedContribution {
  const _CollectedContribution({
    required this.contribution,
    required this.providerIndex,
    required this.contributionIndex,
  });

  final CliLaunchArgContribution contribution;
  final int providerIndex;
  final int contributionIndex;
}

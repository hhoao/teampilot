import 'cli_launch_context.dart';
import '../cli_tool_definition.dart';
import 'cli_launch_arg_contribution.dart';
import 'cli_launch_arg_provider.dart';
import 'cli_launch_capability_error.dart';

/// Collects, validates, orders, and flattens launch argument contributions.
final class CliLaunchArgAssembler {
  const CliLaunchArgAssembler();

  List<String> assemble(CliToolDefinition tool, CliLaunchContext context) {
    final collected = <_CollectedContribution>[];
    final byKey = <String, CliLaunchArgContribution>{};
    final byExclusiveGroup = <String, CliLaunchArgContribution>{};

    var providerIndex = 0;
    for (final capability in tool.capabilities) {
      if (capability is! CliLaunchArgProvider) {
        continue;
      }

      var contributionIndex = 0;
      for (final contribution in capability.buildLaunchArgs(context)) {
        final previousKey = byKey[contribution.key];
        if (previousKey != null) {
          throw CliLaunchCapabilityException(
            cli: tool.id,
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
              cli: tool.id,
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
      providerIndex++;
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

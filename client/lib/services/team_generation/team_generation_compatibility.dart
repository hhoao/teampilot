import '../../models/team_config.dart';
import '../../models/team_generation_settings.dart';
import '../cli/registry/capabilities/cli_session_capability.dart';
import '../cli/registry/capabilities/mcp_capability.dart';
import '../cli/registry/capabilities/skill_capability.dart';
import '../cli/registry/capabilities/team_behavior_capability.dart';
import '../cli/registry/cli_tool_registry.dart';

/// One typed compatibility issue; [code] drives localized remediation.
final class TeamGenerationIssue {
  const TeamGenerationIssue({
    required this.code,
    this.detail = '',
  });

  final String code;
  final String detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamGenerationIssue &&
          code == other.code &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(code, detail);

  @override
  String toString() => 'TeamGenerationIssue($code, $detail)';
}

/// Result of one capability-composed compatibility evaluation.
final class TeamGenerationCompatibilityResult {
  const TeamGenerationCompatibilityResult({
    required this.issues,
    this.builderSecurityPolicy,
  });

  final List<TeamGenerationIssue> issues;

  /// Policy chosen for the builder session (generator evaluation only).
  final LaunchSecurityPolicy? builderSecurityPolicy;

  bool get isCompatible => issues.isEmpty;
}

/// Capability-composed checks: no `if (cli == …)` branches anywhere.
///
/// - Generator: launch + session + skill + MCP capabilities.
/// - Builder policy: askReadOnlyTrusted when the CLI's session capability
///   declares a representable ask/approval surface, else cliDefault — never
///   fullAccess.
/// - Native pool: every effective entry matches the selected native CLI and
///   the CLI advertises [TeamBehaviorCapability.supportsNativeTeam].
/// - Mixed pool: every preset CLI is launch-supported and session-capable.
final class TeamGenerationCompatibility {
  const TeamGenerationCompatibility({required this.registry});

  final CliToolRegistry registry;

  TeamGenerationCompatibilityResult evaluateGenerator({
    required CliTool cli,
  }) {
    final issues = <TeamGenerationIssue>[];
    final definition = registry.tryGet(cli);
    if (definition == null || !definition.isLaunchSupported) {
      issues.add(
        const TeamGenerationIssue(code: 'generator_launch_unsupported'),
      );
      return TeamGenerationCompatibilityResult(
        issues: issues,
        builderSecurityPolicy: LaunchSecurityPolicy.cliDefault,
      );
    }
    if (registry.capability<CliSessionCapability>(cli) == null) {
      issues.add(
        const TeamGenerationIssue(code: 'generator_session_unsupported'),
      );
    }
    if (registry.capability<SkillCapability>(cli) == null) {
      issues.add(
        const TeamGenerationIssue(code: 'generator_skill_unsupported'),
      );
    }
    if (registry.capability<McpCapability>(cli) == null) {
      issues.add(
        const TeamGenerationIssue(code: 'generator_mcp_unsupported'),
      );
    }
    return TeamGenerationCompatibilityResult(
      issues: issues,
      builderSecurityPolicy: _builderSecurityPolicy(cli),
    );
  }

  TeamGenerationCompatibilityResult evaluateTeamPool({
    required TeamMode mode,
    required CliTool nativeCli,
    required List<EffectiveGenerateModelPoolEntry> pool,
  }) {
    if (pool.isEmpty) {
      return const TeamGenerationCompatibilityResult(
        issues: [TeamGenerationIssue(code: 'model_pool_empty')],
      );
    }
    final issues = <TeamGenerationIssue>[];
    if (mode == TeamMode.native) {
      for (final entry in pool) {
        final behavior =
            registry.capability<TeamBehaviorCapability>(entry.preset.cli);
        if (entry.preset.cli != nativeCli) {
          issues.add(
            TeamGenerationIssue(
              code: 'native_pool_cli_mismatch',
              detail: entry.preset.id,
            ),
          );
        }
        if (behavior?.supportsNativeTeam != true) {
          issues.add(
            const TeamGenerationIssue(code: 'native_team_unsupported'),
          );
        }
      }
    } else {
      for (final entry in pool) {
        final definition = registry.tryGet(entry.preset.cli);
        if (definition == null || !definition.isLaunchSupported) {
          issues.add(
            TeamGenerationIssue(
              code: 'pool_launch_unsupported',
              detail: entry.preset.id,
            ),
          );
        } else if (registry.capability<CliSessionCapability>(
                entry.preset.cli) ==
            null) {
          issues.add(
            TeamGenerationIssue(
              code: 'pool_session_unsupported',
              detail: entry.preset.id,
            ),
          );
        }
      }
    }
    return TeamGenerationCompatibilityResult(issues: issues);
  }

  /// askReadOnlyTrusted when the CLI's session capability exposes an ask /
  /// read-only surface; otherwise cliDefault. Never fullAccess: the builder
  /// must not run with elevated trust merely because generation needs MCP.
  LaunchSecurityPolicy _builderSecurityPolicy(CliTool cli) {
    final session = registry.capability<CliSessionCapability>(cli);
    if (session != null && _representsAskPolicy(session)) {
      return LaunchSecurityPolicy.askReadOnlyTrusted;
    }
    return LaunchSecurityPolicy.cliDefault;
  }

  bool _representsAskPolicy(CliSessionCapability session) {
    // Ask-based approval exists on every session-capable CLI the app can
    // launch; the capability simply marks the CLI as owning a session
    // surface. When a future capability adds an explicit read-only deny,
    // this check narrows there.
    return true;
  }
}

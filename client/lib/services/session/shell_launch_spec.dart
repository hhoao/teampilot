import '../../models/team_config.dart';
import '../cli/cli_tool_adapter.dart';

class LaunchPlan {
  const LaunchPlan({
    required this.env,
    required this.resume,
    required this.taskId,
    required this.cliTeamName,
    required this.memberConfigDir,
    required this.resolvedRoots,
    this.createSessionId,
    this.resumeSessionId,
    this.nativeSessionIdToPersist,
    this.isFreshConversation = true,
    this.toolValue,
    this.warnings = const [],
  });

  final Map<String, String> env;

  /// Whether this launch resumes an existing native session
  /// (`resumeSessionId != null`).
  final bool resume;

  /// Member [SessionMemberBinding.taskId] — our session/member UUID.
  final String taskId;

  /// Native id to pin when **creating** a fresh session (`clientPinned` CLIs'
  /// `--session-id`). `null` when resuming or when the CLI cannot be told an id.
  final String? createSessionId;

  /// Native id to **resume** (CLI-specific resume flag). `null` for a fresh
  /// session. See `docs/session-resume-architecture.md`.
  final String? resumeSessionId;

  /// Native id the caller should persist onto the session-member binding
  /// (cursor pre-allocated / codex+opencode captured). `null` for `clientPinned`
  /// CLIs (native id == [taskId]) and when nothing new was resolved.
  final String? nativeSessionIdToPersist;

  /// Whether this launch starts a conversation with no prior history. Drives
  /// one-time identity seeding for CLIs that inject identity as the opening
  /// prompt (cursor). See `docs/session-resume-architecture.md`.
  final bool isFreshConversation;

  /// Resolved CLI [CliTool.value] for this launch; keys
  /// [nativeSessionIdToPersist] on the session/binding.
  final String? toolValue;

  /// CLI `--team-name` and config-profiles member runtime directory.
  final String cliTeamName;
  final String memberConfigDir;
  final List<String> resolvedRoots;
  final List<String> warnings;
}

/// Config provisioning ([plan]) plus CLI argv context for a single PTY spawn.
///
/// Built by [SessionLifecycleService.prepareShellLaunch]. Personal and team
/// sessions share this type; [launchContext] holds the adapter-facing
/// `TeamIdentity` / `TeamMemberConfig` pair (standalone profiles are converted
/// in the lifecycle layer, not at the terminal boundary).
class ShellLaunchSpec {
  const ShellLaunchSpec({
    required this.plan,
    required this.launchContext,
    required this.sessionTeam,
  });

  final LaunchPlan plan;
  final CliLaunchContext launchContext;

  /// Passed to CLI adapters as `sessionTeam` (`--team-name`, `--team`, …).
  final String sessionTeam;

  /// Lightweight spec when only CLI argv matter (tests, external-terminal preview).
  factory ShellLaunchSpec.teamMember({
    required TeamIdentity team,
    required TeamMemberConfig member,
    String? sessionTeam,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
  }) {
    final runtimeTeam = sessionTeam?.trim().isNotEmpty == true
        ? sessionTeam!.trim()
        : team.name.trim();
    return ShellLaunchSpec(
      plan: LaunchPlan(
        env: const {},
        resume: false,
        taskId: '',
        cliTeamName: runtimeTeam,
        memberConfigDir: '',
        resolvedRoots: const [],
      ),
      launchContext: CliLaunchContext(
        team: team,
        member: member,
        sessionTeam: runtimeTeam,
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
      ),
      sessionTeam: runtimeTeam,
    );
  }
}

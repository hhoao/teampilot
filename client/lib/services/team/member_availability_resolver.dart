import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../cli/preset_resolver.dart';
import '../team_bus/team_bus.dart';
import '../terminal/terminal_session.dart';

/// Pure availability rules shared by [MemberPresenceService] and tests.
abstract final class MemberAvailabilityResolver {
  MemberAvailabilityResolver._();

  /// Computes agent availability for a connected PTY shell.
  static MemberAvailability forConnected({
    required TerminalSession shell,
    required TeamMemberConfig member,
    required TeamProfile team,
    required TeamMode teamMode,
    required List<CliPreset> globalPresets,
    TeamBus? bus,
    required bool claudeRosterWorking,
    required bool usesClaudeRoster,
    required bool usesShellActivity,
  }) {
    if (!shell.activityTracker.isBootFrameReady) {
      return MemberAvailability.booting;
    }

    if (teamMode == TeamMode.mixed && bus != null) {
      return _mixed(
        bus: bus,
        shell: shell,
        member: member,
        team: team,
        globalPresets: globalPresets,
      );
    }

    if (usesClaudeRoster) {
      return claudeRosterWorking
          ? MemberAvailability.working
          : MemberAvailability.idle;
    }

    if (usesShellActivity) {
      return shell.activityTracker.isWorking
          ? MemberAvailability.working
          : MemberAvailability.idle;
    }

    return MemberAvailability.idle;
  }

  static MemberAvailability _mixed({
    required TeamBus bus,
    required TerminalSession shell,
    required TeamMemberConfig member,
    required TeamProfile team,
    required List<CliPreset> globalPresets,
  }) {
    final memberId = member.id;
    if (bus.isMemberInTurn(memberId)) {
      return MemberAvailability.working;
    }
    if (bus.isWaitingForMessage(memberId)) {
      return MemberAvailability.idle;
    }

    final forceWait = member.effectiveForceWaitBeforeStop(
      team,
      launchCli: memberLaunchCli(
        team: team,
        member: member,
        globalPresets: globalPresets,
      ),
    );
    if (forceWait) {
      // TUI stable but agent loop not yet parked in wait_for_message.
      return MemberAvailability.booting;
    }

    // Push-CLI (cursor): idle-at-prompt when quiet. PTY bytes only count after
    // a bus turn signal (user submit → active, mail/task doorbell), not startup
    // TUI churn.
    if (!_pushCliAllowsPtyWorking(bus: bus, memberId: memberId)) {
      return MemberAvailability.idle;
    }
    return shell.activityTracker.isWorking
        ? MemberAvailability.working
        : MemberAvailability.idle;
  }

  /// Automation / scheduled message inject: safe once startup finished (TUI
  /// frame stable; mixed forceWait CLIs also parked in `wait_for_message`).
  static bool isReadyForAutomationInput({
    required TerminalSession shell,
    required TeamMemberConfig member,
    required TeamProfile team,
    required TeamMode teamMode,
    required List<CliPreset> globalPresets,
    TeamBus? bus,
    required bool claudeRosterWorking,
    required bool usesClaudeRoster,
    required bool usesShellActivity,
  }) {
    return forConnected(
          shell: shell,
          member: member,
          team: team,
          teamMode: teamMode,
          globalPresets: globalPresets,
          bus: bus,
          claudeRosterWorking: claudeRosterWorking,
          usesClaudeRoster: usesClaudeRoster,
          usesShellActivity: usesShellActivity,
        ) !=
        MemberAvailability.booting;
  }

  /// Gate for push-CLI PTY heuristics — avoids boot-time repaint false positives.
  static bool _pushCliAllowsPtyWorking({
    required TeamBus bus,
    required String memberId,
  }) {
    if (bus.isMemberInTurn(memberId)) return true;
    return bus.memberById(memberId)?.doorbelled ?? false;
  }
}

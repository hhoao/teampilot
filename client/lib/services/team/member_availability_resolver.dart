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
    if (bus.isWaitingForMessage(memberId)) {
      return MemberAvailability.idle;
    }

    // Operator send / compose landing — same latch as personal mode.
    if (shell.userTurnActive) {
      return MemberAvailability.working;
    }

    // PTY quiet wins over bus in-turn / doorbell: members panel should reflect
    // visible terminal stillness even when mail is queued unconsumed.
    if (!shell.activityTracker.isWorking) {
      return MemberAvailability.idle;
    }

    if (bus.isMemberInTurn(memberId)) {
      return MemberAvailability.working;
    }

    // Push-CLI (cursor): PTY bytes only count after a bus turn signal (user
    // submit → active, mail/task doorbell), not startup TUI churn.
    if (!_pushCliAllowsPtyWorking(bus: bus, memberId: memberId)) {
      return MemberAvailability.idle;
    }
    return MemberAvailability.working;
  }

  /// Automation / scheduled message inject: safe once the TUI boot frame is
  /// stable. Mixed forceWait CLIs must also be parked in `wait_for_message`.
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
    if (!shell.activityTracker.isBootFrameReady) return false;
    if (teamMode == TeamMode.mixed && bus != null) {
      final launchCli = memberLaunchCli(
        team: team,
        member: member,
        globalPresets: globalPresets,
      );
      if (member.effectiveForceWaitBeforeStop(team, launchCli: launchCli) &&
          !bus.isWaitingForMessage(member.id)) {
        return false;
      }
    }
    return true;
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

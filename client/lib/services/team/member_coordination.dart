import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/presence_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../team_bus/team_bus.dart';
import '../terminal/terminal_session.dart';
import 'member_coordination_scope.dart';

export 'member_coordination_scope.dart' show MemberCoordinationScope;

enum MemberCoordinationKind {
  personal,
  mixed,
  nativeClaudeRoster,
  nativeShellActivity,
}

/// Turn latch, idle-watch, and availability policy for one connected member.
sealed class MemberCoordination {
  const MemberCoordination(this.scope);

  final MemberCoordinationScope scope;

  TerminalSession get shell => scope.shell;
  TeamMemberConfig get member => scope.member;
  TeamBus? get bus => scope.bus;

  bool inTurn({required bool pendingDelivery});
  void latchTurnStarted();
  void endTurn();
  MemberAvailability availability();
  bool countsAsSessionWorkingWhileBooting();
  bool isReadyForAutomationInput({bool directToPty = false});

  factory MemberCoordination.resolve({
    required TerminalSession shell,
    required TeamMemberConfig member,
    required TeamProfile team,
    required TeamMode teamMode,
    required List<CliPreset> globalPresets,
    TeamBus? bus,
    bool? isPersonalSession,
    bool claudeRosterWorking = false,
    bool usesClaudeRoster = false,
    bool usesShellActivity = false,
    CliToolRegistry? cliToolRegistry,
  }) {
    final personal =
        isPersonalSession ??
        MemberCoordinationScope.inferPersonalFromLegacyFlags(
          teamMode: teamMode,
          bus: bus,
          usesClaudeRoster: usesClaudeRoster,
          usesShellActivity: usesShellActivity,
        );
    final coordinationScope = MemberCoordinationScope(
      shell: shell,
      member: member,
      team: team,
      teamMode: teamMode,
      globalPresets: globalPresets,
      bus: bus,
      claudeRosterWorking: claudeRosterWorking,
    );
    final registry = cliToolRegistry ?? CliToolRegistry.builtIn();
    final presenceCap = registry.capability<PresenceCapability>(team.cli);
    final kind = _kindFor(
      isPersonalSession: personal,
      teamMode: teamMode,
      bus: bus,
      usesClaudeRoster: presenceCap?.usesClaudeRoster ?? usesClaudeRoster,
      usesShellActivity: presenceCap?.usesShellActivity ?? usesShellActivity,
    );
    return switch (kind) {
      MemberCoordinationKind.personal =>
        PersonalMemberCoordination(coordinationScope),
      MemberCoordinationKind.mixed => MixedMemberCoordination(coordinationScope),
      MemberCoordinationKind.nativeClaudeRoster =>
        NativeClaudeRosterCoordination(coordinationScope),
      MemberCoordinationKind.nativeShellActivity =>
        NativeShellActivityCoordination(coordinationScope),
    };
  }

  static MemberCoordinationKind _kindFor({
    required bool isPersonalSession,
    required TeamMode teamMode,
    required TeamBus? bus,
    required bool usesClaudeRoster,
    required bool usesShellActivity,
  }) {
    if (teamMode == TeamMode.mixed && bus != null) {
      return MemberCoordinationKind.mixed;
    }
    if (isPersonalSession) return MemberCoordinationKind.personal;
    if (usesClaudeRoster) return MemberCoordinationKind.nativeClaudeRoster;
    if (usesShellActivity) return MemberCoordinationKind.nativeShellActivity;
    return MemberCoordinationKind.personal;
  }

  MemberAvailability _bootingOr(MemberAvailability whenReady) {
    if (!shell.activityTracker.isBootFrameReady) {
      return MemberAvailability.booting;
    }
    return whenReady;
  }
}

/// Shell [userTurnActive] latch shared by personal and native single-CLI modes.
abstract base class ShellLatchCoordination extends MemberCoordination {
  const ShellLatchCoordination(super.scope);

  @override
  bool inTurn({required bool pendingDelivery}) =>
      shell.userTurnActive || pendingDelivery;

  @override
  void latchTurnStarted() => shell.markUserTurnStarted();

  @override
  void endTurn() => shell.markUserTurnIdle();

  @override
  bool isReadyForAutomationInput({bool directToPty = false}) =>
      shell.activityTracker.isBootFrameReady;
}

final class PersonalMemberCoordination extends ShellLatchCoordination {
  const PersonalMemberCoordination(super.scope);

  @override
  MemberAvailability availability() => _bootingOr(
    shell.userTurnActive
        ? MemberAvailability.working
        : MemberAvailability.idle,
  );

  @override
  bool countsAsSessionWorkingWhileBooting() {
    if (availability() != MemberAvailability.booting) return false;
    return shell.userTurnActive || shell.activityTracker.isWorking;
  }
}

final class NativeClaudeRosterCoordination extends ShellLatchCoordination {
  const NativeClaudeRosterCoordination(super.scope);

  @override
  MemberAvailability availability() => _bootingOr(
    scope.claudeRosterWorking
        ? MemberAvailability.working
        : MemberAvailability.idle,
  );

  @override
  bool countsAsSessionWorkingWhileBooting() => false;
}

final class NativeShellActivityCoordination extends ShellLatchCoordination {
  const NativeShellActivityCoordination(super.scope);

  @override
  MemberAvailability availability() => _bootingOr(
    shell.activityTracker.isWorking
        ? MemberAvailability.working
        : MemberAvailability.idle,
  );

  @override
  bool countsAsSessionWorkingWhileBooting() => false;
}

final class MixedMemberCoordination extends MemberCoordination {
  const MixedMemberCoordination(super.scope);

  @override
  bool inTurn({required bool pendingDelivery}) {
    final b = bus;
    if (b == null) return false;
    final memberId = member.id;
    if (b.isWaitingForMessage(memberId)) return false;
    return b.isMemberInTurn(memberId);
  }

  @override
  void latchTurnStarted() => bus?.markTurnStarted(member.id);

  @override
  void endTurn() => bus?.onMemberIdle(member.id, fromPtyQuietWatch: true);

  @override
  MemberAvailability availability() => _bootingOr(_mixedAvailability());

  MemberAvailability _mixedAvailability() {
    final b = bus!;
    final memberId = member.id;
    if (b.isWaitingForMessage(memberId)) {
      return MemberAvailability.idle;
    }
    if (b.isMemberInTurn(memberId)) {
      return MemberAvailability.working;
    }
    if (!shell.activityTracker.isWorking) {
      return MemberAvailability.idle;
    }
    if (!_pushCliAllowsPtyWorking(b, memberId)) {
      return MemberAvailability.idle;
    }
    return MemberAvailability.working;
  }

  @override
  bool countsAsSessionWorkingWhileBooting() => false;

  @override
  bool isReadyForAutomationInput({bool directToPty = false}) {
    if (!shell.activityTracker.isBootFrameReady) return false;
    if (directToPty) return true;
    final b = bus;
    if (b == null) return true;
    final launchCli = memberLaunchCli(
      team: scope.team,
      member: member,
      globalPresets: scope.globalPresets,
    );
    if (member.effectiveForceWaitBeforeStop(scope.team, launchCli: launchCli) &&
        !b.isWaitingForMessage(member.id)) {
      return false;
    }
    return true;
  }

  static bool _pushCliAllowsPtyWorking(TeamBus bus, String memberId) {
    if (bus.isMemberInTurn(memberId)) return true;
    return bus.memberById(memberId)?.doorbelled ?? false;
  }
}

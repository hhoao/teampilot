import '../../../models/app_session.dart';
import '../../../models/cli_preset.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';

/// Builds patched sessions and persists continue chrome edits for [ChatCubit].
class SessionContinueOverridesController {
  const SessionContinueOverridesController();

  /// Merges a continue-chrome patch onto the tab's cached session without
  /// dropping launch-time fields (native resume ids, launchState) that only
  /// exist on the cache. Restart / member-reconnect read the cache, so keep
  /// the switched provider/model/effort/preset and overrides in sync there.
  static AppSession mergeOntoTabCache({
    required AppSession cached,
    required AppSession patched,
  }) {
    return cached.copyWith(
      display: patched.display,
      presetId: patched.presetId,
      provider: patched.provider,
      model: patched.model,
      effort: patched.effort,
      continueOverrides: patched.continueOverrides,
    );
  }

  AppSession? sessionIn(List<AppSession> sessions, String sessionId) {
    for (final session in sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }

  /// Returns null when [preset.cli] does not match [lockedCli].
  AppSession? patchPreset({
    required AppSession session,
    required CliPreset preset,
    String? memberId,
    required CliTool lockedCli,
  }) {
    if (preset.cli != lockedCli) return null;

    final trimmedMemberId = memberId?.trim();
    if (trimmedMemberId == null || trimmedMemberId.isEmpty) {
      return session.copyWith(
        presetId: preset.id,
        provider: preset.provider,
        model: preset.model,
        effort: preset.effort,
      );
    }

    final updatedMembers = Map<String, SessionMemberContinueOverride>.from(
      session.continueOverrides.memberOverrides,
    );
    updatedMembers[trimmedMemberId] = SessionMemberContinueOverride(
      presetId: preset.id,
      provider: preset.provider,
      model: preset.model,
      effort: preset.effort.isEmpty ? null : preset.effort,
    );
    return session.copyWith(
      continueOverrides: session.continueOverrides.copyWith(
        memberOverrides: updatedMembers,
      ),
    );
  }

  /// Returns null when [session] is not Simple.
  AppSession? patchCustom({
    required AppSession session,
    required String provider,
    required String model,
    required String effort,
  }) {
    if (!session.isSimple) return null;
    return session.copyWith(
      presetId: '',
      provider: provider,
      model: model,
      effort: effort,
    );
  }

  Future<void> persistPreset({
    required SessionRepository repo,
    required AppSession patched,
    String? memberId,
  }) {
    final trimmedMemberId = memberId?.trim();
    if (trimmedMemberId == null || trimmedMemberId.isEmpty) {
      return repo.updateSimpleLaunchIdentity(
        patched.sessionId,
        presetId: patched.presetId,
        provider: patched.provider,
        model: patched.model,
        effort: patched.effort,
      );
    }
    return repo.updateContinueOverrides(
      patched.sessionId,
      patched.continueOverrides,
    );
  }

  Future<void> persistCustom({
    required SessionRepository repo,
    required AppSession patched,
  }) {
    return repo.updateSimpleLaunchIdentity(
      patched.sessionId,
      presetId: '',
      provider: patched.provider,
      model: patched.model,
      effort: patched.effort,
    );
  }
}

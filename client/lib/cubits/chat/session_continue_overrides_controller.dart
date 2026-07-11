import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';

/// Builds patched sessions and persists continue chrome edits for [ChatCubit].
class SessionContinueOverridesController {
  const SessionContinueOverridesController();

  AppSession? sessionIn(List<AppSession> sessions, String sessionId) {
    for (final session in sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }

  AppSession patchPermission({
    required AppSession session,
    required bool dangerouslySkipPermissions,
    String? memberId,
  }) {
    final trimmedMemberId = memberId?.trim();
    if (trimmedMemberId == null || trimmedMemberId.isEmpty) {
      return session.copyWith(
        continueOverrides: session.continueOverrides.copyWith(
          dangerouslySkipPermissions: dangerouslySkipPermissions,
        ),
      );
    }

    final existing = session.continueOverrides.memberOverrides[trimmedMemberId];
    final updatedMembers = Map<String, SessionMemberContinueOverride>.from(
      session.continueOverrides.memberOverrides,
    );
    updatedMembers[trimmedMemberId] =
        (existing ?? const SessionMemberContinueOverride()).copyWith(
          dangerouslySkipPermissions: dangerouslySkipPermissions,
        );
    return session.copyWith(
      continueOverrides: session.continueOverrides.copyWith(
        memberOverrides: updatedMembers,
      ),
    );
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

    final existing = session.continueOverrides.memberOverrides[trimmedMemberId];
    final updatedMembers = Map<String, SessionMemberContinueOverride>.from(
      session.continueOverrides.memberOverrides,
    );
    updatedMembers[trimmedMemberId] = SessionMemberContinueOverride(
      presetId: preset.id,
      provider: preset.provider,
      model: preset.model,
      effort: preset.effort.isEmpty ? null : preset.effort,
      dangerouslySkipPermissions: existing?.dangerouslySkipPermissions,
    );
    return session.copyWith(
      continueOverrides: session.continueOverrides.copyWith(
        memberOverrides: updatedMembers,
      ),
    );
  }

  Future<void> persistPermission({
    required SessionRepository repo,
    required AppSession patched,
  }) {
    return repo.updateContinueOverrides(
      patched.sessionId,
      patched.continueOverrides,
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
}

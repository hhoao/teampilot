import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';
import '../../models/app_session.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/team_config.dart';

/// Launch / CLI identity for [SessionChatView] — excludes paint-only fields
/// ([AppSession.display], timestamps, pin, sortOrder) so first-message title
/// capture does not rebuild the history thread.
@immutable
class SessionChatIdentity {
  const SessionChatIdentity({
    required this.sessionId,
    required this.workspaceId,
    required this.sessionTeam,
    required this.profileId,
    this.cli,
    required this.provider,
    required this.model,
    required this.effort,
    required this.presetId,
    required this.expertKey,
    required this.continueOverrides,
  });

  final String sessionId;
  final String workspaceId;
  final String sessionTeam;
  final String profileId;
  final CliTool? cli;
  final String provider;
  final String model;
  final String effort;
  final String presetId;
  final String expertKey;
  final SessionContinueOverrides continueOverrides;

  bool get isSimple => sessionTeam.trim().isEmpty;

  factory SessionChatIdentity.fromSession(AppSession session) {
    return SessionChatIdentity(
      sessionId: session.sessionId,
      workspaceId: session.workspaceId,
      sessionTeam: session.sessionTeam,
      profileId: session.profileId,
      cli: session.cli,
      provider: session.provider,
      model: session.model,
      effort: session.effort,
      presetId: session.presetId,
      expertKey: session.expertKey,
      continueOverrides: session.continueOverrides,
    );
  }

  factory SessionChatIdentity.fromChatState(ChatState state, String sessionId) {
    return tryFromChatState(state, sessionId) ??
        SessionChatIdentity(
          sessionId: sessionId,
          workspaceId: '',
          sessionTeam: '',
          profileId: '',
          provider: '',
          model: '',
          effort: '',
          presetId: '',
          expertKey: '',
          continueOverrides: const SessionContinueOverrides(),
        );
  }

  static SessionChatIdentity? tryFromChatState(
    ChatState state,
    String sessionId,
  ) {
    for (final s in state.sessions) {
      if (s.sessionId == sessionId) return SessionChatIdentity.fromSession(s);
    }
    return null;
  }

  /// Overlay identity fields onto [base] (constructor snapshot / folders).
  AppSession applyTo(AppSession base) {
    if (sessionId != base.sessionId) return base;
    return base.copyWith(
      sessionTeam: sessionTeam,
      profileId: profileId,
      cli: cli,
      provider: provider,
      model: model,
      effort: effort,
      presetId: presetId,
      expertKey: expertKey,
      continueOverrides: continueOverrides,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionChatIdentity &&
        sessionId == other.sessionId &&
        workspaceId == other.workspaceId &&
        sessionTeam == other.sessionTeam &&
        profileId == other.profileId &&
        cli == other.cli &&
        provider == other.provider &&
        model == other.model &&
        effort == other.effort &&
        presetId == other.presetId &&
        expertKey == other.expertKey &&
        continueOverrides == other.continueOverrides;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    workspaceId,
    sessionTeam,
    profileId,
    cli,
    provider,
    model,
    effort,
    presetId,
    expertKey,
    continueOverrides,
  );
}

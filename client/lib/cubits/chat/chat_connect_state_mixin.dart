import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/team/team_config_launch_validator.dart';
import '../../utils/logging/logger.dart';
import '../../utils/session/session_launch_error.dart';
import '../../models/member_remote_provision_progress.dart';
import '../session/session_phase.dart';
import '../session/session_pod.dart';
import 'chat_tab_store.dart';
import 'model/chat_state.dart';

/// Launch-error / connecting state machine over ChatState. Mixed into ChatCubit
/// so it can call emit/state/isClosed directly (kept as the single emit owner).
mixin ChatConnectStateMixin on Cubit<ChatState> {
  ChatTabStore get tabStore;

  void onTabRunningChanged();

  // Pod registry (implemented by ChatCubit) so connect lifecycle drives the
  // per-session phase.
  SessionPod? podRuntime(String sessionId);
  SessionPod ensurePodRuntime(String sessionId);
  bool isSessionConnecting(String sessionId);
  bool get hasConnectingSession;
  void setMaterializingInFlight(bool value);

  void beginSessionConnect(String sessionId) {
    appLogger.d('[session-launch] connecting start session=$sessionId');
    clearLaunchError(sessionId);
    if (sessionId == 'pending') {
      // Pre-session materialization (no real pod exists yet).
      setMaterializingInFlight(true);
      return;
    }
    ensurePodRuntime(sessionId).setPhase(SessionPhase.connecting);
  }

  void setLaunchError(String sessionId, String rawMessage) {
    final message = formatSessionLaunchError(rawMessage);
    if (message.isEmpty) return;
    final tab = tabStore.openTabBySessionId(sessionId);
    if (tab != null) {
      tab.info = tab.info.copyWith(launchError: message);
      if (tabStore.activeIndexOfSession(sessionId) != -1) {
        emit(
          state.copyWith(
            tabs: tabStore.activeTabInfos(),
            clearSessionLaunchError: true,
            stateVersion: state.stateVersion + 1,
          ),
        );
      }
      return;
    }
    emit(
      state.copyWith(
        sessionLaunchError: message,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void clearLaunchError(String sessionId) {
    var tabChanged = false;
    final tab = tabStore.openTabBySessionId(sessionId);
    if (tab != null && tab.info.launchError != null) {
      tab.info = tab.info.copyWith(clearLaunchError: true);
      tabChanged = tabStore.activeIndexOfSession(sessionId) != -1;
    }
    if (!tabChanged && state.sessionLaunchError == null) return;
    emit(
      state.copyWith(
        tabs: tabChanged ? tabStore.activeTabInfos() : state.tabs,
        clearSessionLaunchError: true,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void failSessionConnect(String sessionId, String rawMessage) {
    appLogger.w(
      '[session-launch] connecting failed session=$sessionId: $rawMessage',
    );
    setLaunchError(sessionId, rawMessage);
    if (sessionId == 'pending') {
      setMaterializingInFlight(false);
      updateTabRunning(sessionId);
      return;
    }
    final pod = podRuntime(sessionId);
    if (pod != null) {
      pod.setPhase(SessionPhase.error);
      pod.setLaunchError(rawMessage);
    }
    updateTabRunning(sessionId);
  }

  void finishSessionConnect(String sessionId) {
    updateTabRunning(sessionId);
    if (isClosed) return;
    if (sessionId == 'pending') {
      setMaterializingInFlight(false);
      return;
    }
    podRuntime(sessionId)?.setPhase(SessionPhase.running);
  }

  void updateTabRunning(String tabId) {
    final tab = tabStore.openTabBySessionId(tabId);
    if (tab == null) return;
    tab.info = tab.info.copyWith(isRunning: tab.isRunning);
    if (tabStore.activeIndexOfSession(tabId) == -1) {
      onTabRunningChanged();
      return;
    }
    emit(
      state.copyWith(
        tabs: tabStore.activeTabInfos(),
        stateVersion: state.stateVersion + 1,
      ),
    );
    onTabRunningChanged();
  }

  void emitLaunchWarnings(List<String> warnings) {
    if (warnings.isEmpty || isClosed) return;
    for (final warning in warnings) {
      appLogger.d('[session-launch] $warning');
    }
    emit(
      state.copyWith(
        snackbarMessage: warnings.first,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void clearSnackbarMessage() {
    if (isClosed || state.snackbarMessage == null) return;
    emit(state.copyWith(clearSnackbarMessage: true));
  }

  /// Surfaces incomplete team config (provider/model/CLI) found at session open.
  /// No-op when there are no issues — launch itself is never blocked.
  void emitTeamConfigValidation(TeamConfigValidation validation) {
    if (isClosed || !validation.hasIssues) return;
    emit(
      state.copyWith(
        teamConfigValidation: validation,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void setMemberRemoteProvisionProgress(
    String sessionId,
    String memberId,
    MemberRemoteProvisionProgress? progress,
  ) {
    if (isClosed) return;
    final tab = tabStore.openTabBySessionId(sessionId);
    if (tab == null) return;
    final key = memberId.trim();
    if (key.isEmpty) return;
    if (progress == null) {
      if (!tab.memberRemoteProvision.containsKey(key)) return;
      tab.memberRemoteProvision.remove(key);
    } else {
      tab.memberRemoteProvision[key] = progress;
    }
    emit(state.copyWith(stateVersion: state.stateVersion + 1));
  }

  void clearTeamConfigValidation() {
    if (isClosed || state.teamConfigValidation == null) return;
    emit(state.copyWith(clearTeamConfigValidation: true));
  }
}

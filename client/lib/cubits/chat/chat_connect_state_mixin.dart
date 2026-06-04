import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/team/team_config_launch_validator.dart';
import '../../utils/session_launch_error.dart';
import 'chat_tab_store.dart';
import 'model/chat_state.dart';

/// Launch-error / connecting state machine over ChatState. Mixed into ChatCubit
/// so it can call emit/state/isClosed directly (kept as the single emit owner).
mixin ChatConnectStateMixin on Cubit<ChatState> {
  ChatTabStore get tabStore;

  void onTabRunningChanged();

  void beginSessionConnect(String sessionId) {
    clearLaunchError(sessionId);
    if (state.sessionConnectingId == sessionId) return;
    emit(
      state.copyWith(
        sessionConnectingId: sessionId,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void setLaunchError(String sessionId, String rawMessage) {
    final message = formatSessionLaunchError(rawMessage);
    if (message.isEmpty) return;
    final idx = tabStore.indexOfSession(sessionId);
    if (idx != -1) {
      tabStore.tabs[idx].info = tabStore.tabs[idx].info.copyWith(
        launchError: message,
      );
      emit(
        state.copyWith(
          tabs: tabStore.toInfos(),
          clearSessionLaunchError: true,
          stateVersion: state.stateVersion + 1,
        ),
      );
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
    final idx = tabStore.indexOfSession(sessionId);
    if (idx != -1 && tabStore.tabs[idx].info.launchError != null) {
      tabStore.tabs[idx].info = tabStore.tabs[idx].info.copyWith(
        clearLaunchError: true,
      );
      tabChanged = true;
    }
    if (!tabChanged && state.sessionLaunchError == null) return;
    emit(
      state.copyWith(
        tabs: tabChanged ? tabStore.toInfos() : state.tabs,
        clearSessionLaunchError: true,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void failSessionConnect(String sessionId, String rawMessage) {
    setLaunchError(sessionId, rawMessage);
    finishSessionConnect(sessionId);
  }

  void finishSessionConnect(String sessionId) {
    updateTabRunning(sessionId);
    if (state.sessionConnectingId != sessionId) return;
    emit(
      state.copyWith(
        clearSessionConnectingId: true,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void updateTabRunning(String tabId) {
    final idx = tabStore.indexOfSession(tabId);
    if (idx == -1) return;
    tabStore.tabs[idx].info = tabStore.tabs[idx].info.copyWith(
      isRunning: tabStore.tabs[idx].isRunning,
    );
    emit(
      state.copyWith(
        tabs: tabStore.toInfos(),
        stateVersion: state.stateVersion + 1,
      ),
    );
    onTabRunningChanged();
  }

  void emitLaunchWarnings(List<String> warnings) {
    if (warnings.isEmpty || isClosed) return;
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

  void clearTeamConfigValidation() {
    if (isClosed || state.teamConfigValidation == null) return;
    emit(state.copyWith(clearTeamConfigValidation: true));
  }
}

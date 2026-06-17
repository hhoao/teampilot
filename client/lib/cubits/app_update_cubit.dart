import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_release_info.dart';
import '../repositories/app_settings_repository.dart';
import '../services/app/app_update_installer.dart';
import '../services/app/app_update_service.dart';

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  error,
}

class AppUpdateState extends Equatable {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.currentVersionLabel = '',
    this.availableRelease,
    this.downloadProgress = 0,
    this.errorMessage,
    this.autoCheckEnabled = true,
    this.skippedVersion,
    this.promptRelease,
  });

  final AppUpdateStatus status;
  final String currentVersionLabel;
  final AppReleaseInfo? availableRelease;
  final double downloadProgress;
  final String? errorMessage;

  /// Whether the app silently checks for updates on startup.
  final bool autoCheckEnabled;

  /// Version the user chose to skip; the startup prompt is suppressed for it.
  final String? skippedVersion;

  /// One-shot signal: when non-null, the UI should surface the update dialog
  /// for this release. Cleared via [AppUpdateCubit.consumePrompt].
  final AppReleaseInfo? promptRelease;

  bool get isBusy =>
      status == AppUpdateStatus.checking ||
      status == AppUpdateStatus.downloading ||
      status == AppUpdateStatus.installing;

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    String? currentVersionLabel,
    AppReleaseInfo? availableRelease,
    bool clearRelease = false,
    double? downloadProgress,
    String? errorMessage,
    bool clearError = false,
    bool? autoCheckEnabled,
    String? skippedVersion,
    bool clearSkippedVersion = false,
    AppReleaseInfo? promptRelease,
    bool clearPrompt = false,
  }) => AppUpdateState(
    status: status ?? this.status,
    currentVersionLabel: currentVersionLabel ?? this.currentVersionLabel,
    availableRelease: clearRelease
        ? null
        : (availableRelease ?? this.availableRelease),
    downloadProgress: downloadProgress ?? this.downloadProgress,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    autoCheckEnabled: autoCheckEnabled ?? this.autoCheckEnabled,
    skippedVersion: clearSkippedVersion
        ? null
        : (skippedVersion ?? this.skippedVersion),
    promptRelease: clearPrompt ? null : (promptRelease ?? this.promptRelease),
  );

  @override
  List<Object?> get props => [
    status,
    currentVersionLabel,
    availableRelease,
    downloadProgress,
    errorMessage,
    autoCheckEnabled,
    skippedVersion,
    promptRelease,
  ];
}

class AppUpdateCubit extends Cubit<AppUpdateState> {
  AppUpdateCubit({
    AppUpdateService? service,
    AppUpdateInstaller? installer,
    AppSettingsRepository? settings,
  }) : _service = service ?? AppUpdateService(),
       _installer = installer ?? AppUpdateInstaller(),
       _settings = settings,
       super(const AppUpdateState());

  final AppUpdateService _service;
  final AppUpdateInstaller _installer;
  final AppSettingsRepository? _settings;
  File? _downloadedPackage;

  /// Loads persisted preferences (auto-check toggle, skipped version) and the
  /// current version label. Safe to call before any check.
  Future<void> loadPreferences() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      final enabled = await settings.loadAutoCheckUpdatesEnabled();
      final skipped = await settings.loadSkippedUpdateVersion();
      emit(
        state.copyWith(
          autoCheckEnabled: enabled,
          skippedVersion: skipped,
          clearSkippedVersion: skipped == null,
        ),
      );
    } catch (_) {
      // Preferences are best-effort; fall back to defaults silently.
    }
    if (state.currentVersionLabel.isEmpty) {
      await loadCurrentVersion();
    }
  }

  Future<void> setAutoCheckEnabled(bool value) async {
    if (state.autoCheckEnabled == value) return;
    emit(state.copyWith(autoCheckEnabled: value));
    try {
      await _settings?.saveAutoCheckUpdatesEnabled(value);
    } catch (_) {
      // Persisting the toggle is best-effort.
    }
  }

  /// Silent startup check. Does nothing when auto-check is disabled, never
  /// surfaces errors, and only raises [AppUpdateState.promptRelease] when an
  /// update newer than any skipped version is found.
  Future<void> autoCheckOnStartup() async {
    await loadPreferences();
    if (!state.autoCheckEnabled) return;
    try {
      final result = await _service.checkForUpdates();
      if (isClosed) return;
      switch (result) {
        case AppUpdateUpToDate():
          // Stay quiet on startup.
          break;
        case AppUpdateAvailable(:final release):
          final skipped = state.skippedVersion;
          if (skipped != null && skipped == release.version.toString()) {
            // User asked not to be reminded about this exact version.
            emit(
              state.copyWith(
                status: AppUpdateStatus.available,
                availableRelease: release,
              ),
            );
            return;
          }
          emit(
            state.copyWith(
              status: AppUpdateStatus.available,
              availableRelease: release,
              promptRelease: release,
            ),
          );
      }
    } catch (_) {
      // Network/API failures must not interrupt startup.
    }
  }

  /// Clears the one-shot prompt signal after the dialog has been shown.
  void consumePrompt() {
    if (state.promptRelease == null) return;
    emit(state.copyWith(clearPrompt: true));
  }

  /// Remembers the prompted version so startup will not surface it again.
  Future<void> skipPromptedVersion() async {
    final release = state.promptRelease ?? state.availableRelease;
    final version = release?.version.toString();
    emit(
      state.copyWith(
        clearPrompt: true,
        skippedVersion: version,
        clearSkippedVersion: version == null,
      ),
    );
    if (version != null) {
      try {
        await _settings?.saveSkippedUpdateVersion(version);
      } catch (_) {
        // Best-effort persistence.
      }
    }
  }

  Future<void> loadCurrentVersion() async {
    try {
      final label = await _service.currentVersionLabel();
      emit(state.copyWith(currentVersionLabel: label, clearError: true));
    } catch (e) {
      emit(
        state.copyWith(
          errorMessage: e.toString(),
          status: AppUpdateStatus.error,
        ),
      );
    }
  }

  Future<void> checkForUpdates() async {
    if (state.isBusy) return;
    emit(
      state.copyWith(
        status: AppUpdateStatus.checking,
        clearError: true,
        clearRelease: true,
        downloadProgress: 0,
      ),
    );

    try {
      if (state.currentVersionLabel.isEmpty) {
        final label = await _service.currentVersionLabel();
        emit(state.copyWith(currentVersionLabel: label));
      }

      final result = await _service.checkForUpdates();
      switch (result) {
        case AppUpdateUpToDate():
          emit(
            state.copyWith(
              status: AppUpdateStatus.upToDate,
              clearRelease: true,
            ),
          );
        case AppUpdateAvailable(:final release):
          emit(
            state.copyWith(
              status: AppUpdateStatus.available,
              availableRelease: release,
            ),
          );
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: AppUpdateStatus.error,
          errorMessage: _messageFor(e),
        ),
      );
    }
  }

  Future<void> downloadAndInstall() async {
    final release = state.availableRelease;
    if (release == null || state.isBusy) return;

    if (kDebugMode) {
      emit(
        state.copyWith(
          status: AppUpdateStatus.error,
          errorMessage:
              'Use a release build to install updates. Debug builds cannot self-update.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: AppUpdateStatus.downloading,
        downloadProgress: 0,
        clearError: true,
      ),
    );

    try {
      _downloadedPackage = await _service.downloadRelease(
        release,
        onProgress: (p) {
          if (!isClosed) {
            emit(
              state.copyWith(
                status: AppUpdateStatus.downloading,
                downloadProgress: p.clamp(0.0, 1.0),
              ),
            );
          }
        },
      );

      emit(state.copyWith(status: AppUpdateStatus.installing));
      await _installer.install(_downloadedPackage!);
    } catch (e) {
      emit(
        state.copyWith(
          status: AppUpdateStatus.error,
          errorMessage: _messageFor(e),
        ),
      );
    }
  }

  void dismissError() {
    emit(
      state.copyWith(
        clearError: true,
        status: state.availableRelease != null
            ? AppUpdateStatus.available
            : AppUpdateStatus.idle,
      ),
    );
  }

  String _messageFor(Object e) {
    if (e is AppUpdateException) return e.message;
    return e.toString();
  }

  @override
  Future<void> close() {
    _service.dispose();
    return super.close();
  }
}

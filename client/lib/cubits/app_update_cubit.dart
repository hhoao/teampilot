import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_release_info.dart';
import '../services/app_update_installer.dart';
import '../services/app_update_service.dart';

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
  });

  final AppUpdateStatus status;
  final String currentVersionLabel;
  final AppReleaseInfo? availableRelease;
  final double downloadProgress;
  final String? errorMessage;

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
  }) => AppUpdateState(
    status: status ?? this.status,
    currentVersionLabel: currentVersionLabel ?? this.currentVersionLabel,
    availableRelease: clearRelease
        ? null
        : (availableRelease ?? this.availableRelease),
    downloadProgress: downloadProgress ?? this.downloadProgress,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );

  @override
  List<Object?> get props => [
    status,
    currentVersionLabel,
    availableRelease,
    downloadProgress,
    errorMessage,
  ];
}

class AppUpdateCubit extends Cubit<AppUpdateState> {
  AppUpdateCubit({
    AppUpdateService? service,
    AppUpdateInstaller? installer,
  }) : _service = service ?? AppUpdateService(),
       _installer = installer ?? AppUpdateInstaller(),
       super(const AppUpdateState());

  final AppUpdateService _service;
  final AppUpdateInstaller _installer;
  File? _downloadedPackage;

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

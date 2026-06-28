import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Coarse startup phases for the home shell — UI uses this for skeletons, not
/// per-repository loading flags.
enum AppBootstrapPhase {
  buildingShell,
  shellReady,
  loadingHomeIndex,
  homeIndexReady,
  warmingAuxiliary,
  ready,
}

class AppBootstrapState extends Equatable {
  const AppBootstrapState({
    this.phase = AppBootstrapPhase.buildingShell,
    this.suppressHomeEntryMotion = false,
    this.showOnboardingWizard = false,
  });

  final AppBootstrapPhase phase;

  /// Skips workspace-home fade/slide on the first frame after the boot gate.
  final bool suppressHomeEntryMotion;

  /// Resolved during bootstrap so [OnboardingGate] does not flash a spinner.
  final bool showOnboardingWizard;

  bool get homeIndexReady =>
      phase == AppBootstrapPhase.homeIndexReady ||
      phase == AppBootstrapPhase.warmingAuxiliary ||
      phase == AppBootstrapPhase.ready;

  bool get isAppReady => phase == AppBootstrapPhase.ready;

  AppBootstrapState copyWith({
    AppBootstrapPhase? phase,
    bool? suppressHomeEntryMotion,
    bool? showOnboardingWizard,
  }) {
    return AppBootstrapState(
      phase: phase ?? this.phase,
      suppressHomeEntryMotion:
          suppressHomeEntryMotion ?? this.suppressHomeEntryMotion,
      showOnboardingWizard: showOnboardingWizard ?? this.showOnboardingWizard,
    );
  }

  @override
  List<Object?> get props =>
      [phase, suppressHomeEntryMotion, showOnboardingWizard];
}

class AppBootstrapCubit extends Cubit<AppBootstrapState> {
  AppBootstrapCubit() : super(const AppBootstrapState());

  void markShellReady() {
    if (state.phase != AppBootstrapPhase.buildingShell) return;
    emit(state.copyWith(phase: AppBootstrapPhase.shellReady));
  }

  void beginHomeIndex() {
    emit(state.copyWith(phase: AppBootstrapPhase.loadingHomeIndex));
  }

  void markHomeIndexReady() {
    emit(state.copyWith(phase: AppBootstrapPhase.homeIndexReady));
  }

  void beginWarmAuxiliary() {
    if (state.phase == AppBootstrapPhase.homeIndexReady) {
      emit(state.copyWith(phase: AppBootstrapPhase.warmingAuxiliary));
    }
  }

  void markAppReady({required bool showOnboardingWizard}) {
    emit(
      state.copyWith(
        phase: AppBootstrapPhase.ready,
        suppressHomeEntryMotion: true,
        showOnboardingWizard: showOnboardingWizard,
      ),
    );
  }

  void dismissOnboardingWizard() {
    if (!state.showOnboardingWizard) return;
    emit(state.copyWith(showOnboardingWizard: false));
  }

  void clearHomeEntryMotion() {
    if (!state.suppressHomeEntryMotion) return;
    emit(state.copyWith(suppressHomeEntryMotion: false));
  }
}

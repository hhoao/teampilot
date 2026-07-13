import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/layout_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography_scale.dart';
import '../repositories/layout_repository.dart';

class LayoutState extends Equatable {
  const LayoutState({
    this.preferences = const LayoutPreferences(),
    this.isLoading = true,
    this.landingRightToolsOverride,
  });

  final LayoutPreferences preferences;
  final bool isLoading;

  /// Compose-only temporary right-tools visibility; never persisted.
  final bool? landingRightToolsOverride;

  LayoutState copyWith({
    LayoutPreferences? preferences,
    bool? isLoading,
    bool? landingRightToolsOverride,
    bool clearLandingRightToolsOverride = false,
  }) {
    return LayoutState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
      landingRightToolsOverride: clearLandingRightToolsOverride
          ? null
          : (landingRightToolsOverride ?? this.landingRightToolsOverride),
    );
  }

  @override
  List<Object?> get props =>
      [preferences, isLoading, landingRightToolsOverride];
}

class LayoutCubit extends Cubit<LayoutState> {
  LayoutCubit({LayoutRepository? repository})
    : _repository = repository,
      super(const LayoutState());

  final LayoutRepository? _repository;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final prefs = await _repository?.load() ?? const LayoutPreferences();
    emit(
      state.copyWith(
        preferences: prefs.copyWith(workspaceTerminalVisible: false),
        isLoading: false,
      ),
    );
  }

  Future<void> _save(LayoutPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    // Bottom terminal starts hidden each launch; only height/sidebar width persist.
    await _repository?.save(
      preferences.copyWith(workspaceTerminalVisible: false),
    );
  }

  Future<void> setPreset(LayoutPreset preset) =>
      _save(state.preferences.copyWith(preset: preset));

  Future<void> setRegionVisibility({
    required bool appRailVisible,
    required bool membersVisible,
    required bool fileTreeVisible,
    bool? gitVisible,
    bool? boardVisible,
  }) {
    return _save(
      state.preferences.copyWith(
        appRailVisible: appRailVisible,
        membersVisible: membersVisible,
        fileTreeVisible: fileTreeVisible,
        gitVisible: gitVisible,
        boardVisible: boardVisible,
      ),
    );
  }

  Future<void> setWorkspaceEntryMode(WorkspaceEntryMode mode) =>
      _save(state.preferences.copyWith(workspaceEntryMode: mode));

  Future<void> setLastOpenedWorkspaceId(String workspaceId) => _save(
    state.preferences.copyWith(lastOpenedWorkspaceId: workspaceId.trim()),
  );

  Future<void> setRightToolsWidth(double width) =>
      _save(state.preferences.copyWith(rightToolsWidth: width));

  Future<void> setRightToolsVisible(bool visible) =>
      _save(state.preferences.copyWith(rightToolsVisible: visible));

  Future<void> setSidebarVisible(bool visible) =>
      _save(state.preferences.copyWith(sidebarVisible: visible));

  Future<void> setSidebarWidth(double width) =>
      _save(state.preferences.copyWith(sidebarWidth: width));

  Future<void> setHomeSidebarWidth(double width) =>
      _save(state.preferences.copyWith(homeSidebarWidth: width));

  Future<void> setWorkspaceNavWidth(double width) =>
      _save(state.preferences.copyWith(workspaceNavWidth: width));

  Future<void> setThemeMode(String mode) =>
      _save(state.preferences.copyWith(themeMode: mode));

  Future<void> setThemeColorPreset(String presetId) => _save(
    state.preferences.copyWith(
      themeColorPreset: normalizeThemeColorPreset(presetId),
    ),
  );

  Future<void> setTypographyScale(String scaleId) => _save(
    state.preferences.copyWith(
      typographyScale: normalizeTypographyScale(scaleId),
    ),
  );

  Future<void> setTypographyScaleCustom(double multiplier) => _save(
    state.preferences.copyWith(
      typographyScale: 'custom',
      typographyScaleCustomMultiplier: clampTypographyCustomMultiplier(
        multiplier,
      ),
    ),
  );

  /// Whole-UI zoom level (relative preset); independent of text size.
  Future<void> setUiZoomScale(String scaleId) => _save(
    state.preferences.copyWith(uiZoomScale: normalizeTypographyScale(scaleId)),
  );

  Future<void> setUiZoomCustom(double multiplier) => _save(
    state.preferences.copyWith(
      uiZoomScale: 'custom',
      uiZoomCustomMultiplier: clampTypographyCustomMultiplier(multiplier),
    ),
  );

  double get _currentUiZoomMultiplier => typographyScaleForPreferences(
    scaleId: state.preferences.uiZoomScale,
    customMultiplier: state.preferences.uiZoomCustomMultiplier,
  ).multiplier;

  /// Steps whole-UI zoom in by [kUiZoomStep], switching to `custom`. [baseline]
  /// is the per-display auto zoom ([autoUiZoomForDevicePixelRatio]) so the
  /// effective (on-screen) zoom stays within [kUiZoomMin]/[kUiZoomMax] —
  /// callers without device context (e.g. tests) may omit it.
  Future<void> zoomIn({double baseline = 1.0}) =>
      _stepUiZoom(kUiZoomStep, baseline: baseline);

  /// See [zoomIn].
  Future<void> zoomOut({double baseline = 1.0}) =>
      _stepUiZoom(-kUiZoomStep, baseline: baseline);

  Future<void> _stepUiZoom(double delta, {required double baseline}) {
    final next = clampUiZoomMultiplierForBaseline(
      _currentUiZoomMultiplier + delta,
      baseline: baseline,
    );
    return setUiZoomCustom(next);
  }

  /// Resets whole-UI zoom back to the auto per-display baseline.
  Future<void> zoomReset() => setUiZoomScale(kDefaultTypographyScaleId);

  Future<void> toggleSidebar() =>
      setSidebarVisible(!state.preferences.sidebarVisible);

  void setLandingRightToolsOverride(bool visible) {
    emit(state.copyWith(landingRightToolsOverride: visible));
  }

  void clearLandingRightToolsOverride() {
    emit(state.copyWith(clearLandingRightToolsOverride: true));
  }

  Future<void> toggleRightTools({bool composeLanding = false}) {
    if (composeLanding) {
      final effective = state.landingRightToolsOverride ?? false;
      setLandingRightToolsOverride(!effective);
      return Future.value();
    }
    return setRightToolsVisible(!state.preferences.rightToolsVisible);
  }

  Future<void> toggleWorkspaceTerminal() =>
      setWorkspaceTerminalVisible(!state.preferences.workspaceTerminalVisible);

  Future<void> setTerminalThemeMode(String mode) =>
      _save(state.preferences.copyWith(terminalThemeMode: mode));

  Future<void> setLocale(String locale) =>
      _save(state.preferences.copyWith(locale: locale));

  Future<void> setUiFontId(String id) =>
      _save(state.preferences.copyWith(uiFontId: normalizeUiFontId(id)));

  Future<void> setMonoFontId(String id) =>
      _save(state.preferences.copyWith(monoFontId: normalizeMonoFontId(id)));

  Future<void> setWorkspaceTerminalVisible(bool visible) =>
      _save(state.preferences.copyWith(workspaceTerminalVisible: visible));

  Future<void> setWorkspaceTerminalHeight(double height) =>
      _save(state.preferences.copyWith(workspaceTerminalHeight: height));

  Future<void> setMarkdownOpenMode(MarkdownOpenMode mode) =>
      _save(state.preferences.copyWith(markdownOpenMode: mode));
}

import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tp_markdown/tp_markdown.dart' show ContentDisplayMode;

import '../models/layout_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography_scale.dart';
import '../repositories/layout_repository.dart';

enum MobileDrawerMode { chat, tools }

class LayoutState extends Equatable {
  const LayoutState({
    this.preferences = const LayoutPreferences(),
    this.isLoading = true,
    this.landingRightToolsOverride,
    this.narrowLeftSuppressed = false,
    this.mobileDrawerMode = MobileDrawerMode.chat,
  });

  final LayoutPreferences preferences;
  final bool isLoading;

  /// Compose-only temporary right-tools visibility; never persisted.
  final bool? landingRightToolsOverride;

  /// Narrow-layout overlay suppress; never persisted.
  final bool narrowLeftSuppressed;

  /// Mobile unified drawer body; session memory only, never persisted.
  final MobileDrawerMode mobileDrawerMode;

  LayoutState copyWith({
    LayoutPreferences? preferences,
    bool? isLoading,
    bool? landingRightToolsOverride,
    bool clearLandingRightToolsOverride = false,
    bool? narrowLeftSuppressed,
    MobileDrawerMode? mobileDrawerMode,
  }) {
    return LayoutState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
      landingRightToolsOverride: clearLandingRightToolsOverride
          ? null
          : (landingRightToolsOverride ?? this.landingRightToolsOverride),
      narrowLeftSuppressed: narrowLeftSuppressed ?? this.narrowLeftSuppressed,
      mobileDrawerMode: mobileDrawerMode ?? this.mobileDrawerMode,
    );
  }

  @override
  List<Object?> get props => [
    preferences,
    isLoading,
    landingRightToolsOverride,
    narrowLeftSuppressed,
    mobileDrawerMode,
  ];
}

class LayoutCubit extends Cubit<LayoutState> {
  LayoutCubit({LayoutRepository? repository})
    : _repository = repository,
      super(const LayoutState());

  final LayoutRepository? _repository;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final prefs = await _repository?.load() ?? const LayoutPreferences();
    // workspaceTerminalVisible is legacy (bottom dock removed); always ignore.
    emit(
      state.copyWith(
        preferences: prefs.copyWith(workspaceTerminalVisible: false),
        isLoading: false,
      ),
    );
  }

  Future<void> _save(LayoutPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    // Keep JSON field for compat but never persist a visible bottom dock.
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

  Future<void> setRightToolsVisible(bool visible) async {
    if (!visible) {
      return _save(state.preferences.copyWith(rightToolsVisible: false));
    }
    final prefs = state.preferences.copyWith(rightToolsVisible: true);
    emit(
      state.copyWith(
        preferences: prefs,
        mobileDrawerMode: MobileDrawerMode.tools,
      ),
    );
    await _repository?.save(prefs.copyWith(workspaceTerminalVisible: false));
  }

  Future<void> setSidebarVisible(bool visible) async {
    if (!visible) {
      return _save(state.preferences.copyWith(sidebarVisible: false));
    }
    final prefs = state.preferences.copyWith(sidebarVisible: true);
    final mode = prefs.rightToolsVisible
        ? MobileDrawerMode.tools
        : MobileDrawerMode.chat;
    emit(state.copyWith(preferences: prefs, mobileDrawerMode: mode));
    await _repository?.save(prefs.copyWith(workspaceTerminalVisible: false));
  }

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

  Future<void> setSessionTabBarVisible(bool visible) =>
      _save(state.preferences.copyWith(sessionTabBarVisible: visible));

  void setLandingRightToolsOverride(bool visible) {
    emit(state.copyWith(landingRightToolsOverride: visible));
  }

  void clearLandingRightToolsOverride() {
    emit(state.copyWith(clearLandingRightToolsOverride: true));
  }

  void setNarrowLeftSuppressed(bool value) {
    if (state.narrowLeftSuppressed == value) return;
    emit(state.copyWith(narrowLeftSuppressed: value));
  }

  void clearNarrowLeftSuppressed() => setNarrowLeftSuppressed(false);

  Future<void> toggleRightTools({bool composeLanding = false}) {
    if (composeLanding) {
      final effective = state.landingRightToolsOverride ?? false;
      setLandingRightToolsOverride(!effective);
      return Future.value();
    }
    return setRightToolsVisible(!state.preferences.rightToolsVisible);
  }

  void openMobileWorkspaceDrawer({bool composeLanding = false}) {
    unawaited(
      _applyMobileDrawerSnapshot(
        mode: state.mobileDrawerMode,
        open: true,
        composeLanding: composeLanding,
      ),
    );
  }

  Future<void> setMobileDrawerMode(
    MobileDrawerMode mode, {
    bool composeLanding = false,
  }) {
    return _applyMobileDrawerSnapshot(
      mode: mode,
      open: true,
      composeLanding: composeLanding,
    );
  }

  void closeMobileWorkspaceDrawer({bool composeLanding = false}) {
    unawaited(
      _applyMobileDrawerSnapshot(
        mode: state.mobileDrawerMode,
        open: false,
        composeLanding: composeLanding,
      ),
    );
  }

  Future<void> _applyMobileDrawerSnapshot({
    required MobileDrawerMode mode,
    required bool open,
    required bool composeLanding,
  }) async {
    final prefs = _mobileDrawerPreferences(
      mode: mode,
      open: open,
      composeLanding: composeLanding,
    );
    final landingOverride = _mobileDrawerLandingOverride(
      mode: mode,
      open: open,
      composeLanding: composeLanding,
    );
    emit(
      state.copyWith(
        preferences: prefs,
        mobileDrawerMode: mode,
        narrowLeftSuppressed: false,
        landingRightToolsOverride: landingOverride,
        clearLandingRightToolsOverride: landingOverride == null,
      ),
    );
    await _repository?.save(
      prefs.copyWith(workspaceTerminalVisible: false),
    );
  }

  LayoutPreferences _mobileDrawerPreferences({
    required MobileDrawerMode mode,
    required bool open,
    required bool composeLanding,
  }) {
    if (!open) {
      return state.preferences.copyWith(
        sidebarVisible: false,
        rightToolsVisible: false,
      );
    }
    return switch (mode) {
      MobileDrawerMode.chat => state.preferences.copyWith(
        sidebarVisible: true,
        rightToolsVisible: false,
      ),
      MobileDrawerMode.tools => state.preferences.copyWith(
        sidebarVisible: false,
        rightToolsVisible: !composeLanding,
      ),
    };
  }

  bool? _mobileDrawerLandingOverride({
    required MobileDrawerMode mode,
    required bool open,
    required bool composeLanding,
  }) {
    if (!composeLanding) return null;
    if (!open) return false;
    return mode == MobileDrawerMode.tools;
  }

  /// No-op: bottom dock removed; shell lives as center workbench tabs.
  Future<void> toggleWorkspaceTerminal() => Future.value();

  Future<void> setTerminalThemeMode(String mode) =>
      _save(state.preferences.copyWith(terminalThemeMode: mode));

  Future<void> setLocale(String locale) =>
      _save(state.preferences.copyWith(locale: locale));

  Future<void> setUiFontId(String id) =>
      _save(state.preferences.copyWith(uiFontId: normalizeUiFontId(id)));

  Future<void> setMonoFontId(String id) =>
      _save(state.preferences.copyWith(monoFontId: normalizeMonoFontId(id)));

  /// No-op: bottom dock removed; keep method for callers / prefs compat.
  Future<void> setWorkspaceTerminalVisible(bool visible) => Future.value();

  Future<void> setWorkspaceTerminalHeight(double height) =>
      _save(state.preferences.copyWith(workspaceTerminalHeight: height));

  Future<void> setMarkdownOpenMode(MarkdownOpenMode mode) =>
      _save(state.preferences.copyWith(markdownOpenMode: mode));

  Future<void> setFilePreviewHost(FilePreviewHost host) =>
      _save(state.preferences.copyWith(filePreviewHost: host));

  Future<void> setCotExpandReasoningOnOpen(bool value) =>
      _save(state.preferences.copyWith(cotExpandReasoningOnOpen: value));

  Future<void> setCotExpandToolsOnOpen(bool value) =>
      _save(state.preferences.copyWith(cotExpandToolsOnOpen: value));

  Future<void> setAutoOpenSubagentPreview(bool value) =>
      _save(state.preferences.copyWith(autoOpenSubagentPreview: value));

  Future<void> setChatUserMessageMode(ContentDisplayMode value) =>
      _save(state.preferences.copyWith(chatUserMessageMode: value));

  Future<void> setChatCodeBlockMode(ContentDisplayMode value) =>
      _save(state.preferences.copyWith(chatCodeBlockMode: value));

  Future<void> setFileCodeBlockMode(ContentDisplayMode value) =>
      _save(state.preferences.copyWith(fileCodeBlockMode: value));

  Future<void> setFoldToolCallCategory(
    AiToolCallCategory category, {
    required bool fold,
  }) {
    final next = {...state.preferences.foldToolCallCategories};
    if (fold) {
      next.add(category);
    } else {
      next.remove(category);
    }
    return _save(state.preferences.copyWith(foldToolCallCategories: next));
  }

  Future<void> setFloatingWorkspaceGeometry({
    double? panelLeft,
    double? panelTop,
    double? panelWidth,
    double? panelHeight,
    double? panelRightInset,
    double? panelBottomInset,
    double? toggleDx,
    double? toggleDy,
    bool? maximized,
  }) => _save(
    state.preferences.copyWith(
      floatingPanelLeft: panelLeft,
      floatingPanelTop: panelTop,
      floatingPanelWidth: panelWidth,
      floatingPanelHeight: panelHeight,
      floatingPanelRightInset: panelRightInset,
      floatingPanelBottomInset: panelBottomInset,
      floatingToggleDx: toggleDx,
      floatingToggleDy: toggleDy,
      floatingMaximized: maximized,
    ),
  );
}

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
  });

  final LayoutPreferences preferences;
  final bool isLoading;

  LayoutState copyWith({LayoutPreferences? preferences, bool? isLoading}) {
    return LayoutState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [preferences, isLoading];
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

  Future<void> setToolPlacement(ToolPanelPlacement placement) =>
      _save(state.preferences.copyWith(toolPlacement: placement));

  Future<void> setToolsArrangement(ToolsArrangement arrangement) =>
      _save(state.preferences.copyWith(toolsArrangement: arrangement));

  Future<void> setRegionVisibility({
    required bool appRailVisible,
    required bool contextSidebarVisible,
    required bool membersVisible,
    required bool fileTreeVisible,
    bool? gitVisible,
  }) {
    return _save(
      state.preferences.copyWith(
        appRailVisible: appRailVisible,
        contextSidebarVisible: contextSidebarVisible,
        membersVisible: membersVisible,
        fileTreeVisible: fileTreeVisible,
        gitVisible: gitVisible,
      ),
    );
  }

  Future<void> setRightToolsWidth(double width) =>
      _save(state.preferences.copyWith(rightToolsWidth: width));

  Future<void> setRightToolsVisible(bool visible) =>
      _save(state.preferences.copyWith(rightToolsVisible: visible));

  Future<void> setSidebarWidth(double width) =>
      _save(state.preferences.copyWith(sidebarWidth: width));

  Future<void> setWorkspaceNavWidth(double width) =>
      _save(state.preferences.copyWith(workspaceNavWidth: width));

  Future<void> setBottomToolsHeight(double height) =>
      _save(state.preferences.copyWith(bottomToolsHeight: height));

  Future<void> setMembersSplit(double split) =>
      _save(state.preferences.copyWith(membersSplit: split));

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

  Future<void> setTerminalThemeMode(String mode) =>
      _save(state.preferences.copyWith(terminalThemeMode: mode));

  Future<void> setLocale(String locale) =>
      _save(state.preferences.copyWith(locale: locale));

  Future<void> setWorkspaceTerminalVisible(bool visible) => _save(
    state.preferences.copyWith(workspaceTerminalVisible: visible),
  );

  Future<void> setWorkspaceTerminalHeight(double height) => _save(
    state.preferences.copyWith(workspaceTerminalHeight: height),
  );

  Future<void> setWorkspaceTerminalSessionSidebarWidth(double width) =>
      _save(
        state.preferences.copyWith(
          workspaceTerminalSessionSidebarWidth: width,
        ),
      );
}

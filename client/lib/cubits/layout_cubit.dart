import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/layout_preferences.dart';
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
    emit(state.copyWith(preferences: prefs, isLoading: false));
  }

  Future<void> _save(LayoutPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    await _repository?.save(preferences);
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
  }) {
    return _save(state.preferences.copyWith(
      appRailVisible: appRailVisible,
      contextSidebarVisible: contextSidebarVisible,
      membersVisible: membersVisible,
      fileTreeVisible: fileTreeVisible,
    ));
  }

  Future<void> setRightToolsWidth(double width) =>
      _save(state.preferences.copyWith(rightToolsWidth: width));

  Future<void> setBottomToolsHeight(double height) =>
      _save(state.preferences.copyWith(bottomToolsHeight: height));

  Future<void> setMembersSplit(double split) =>
      _save(state.preferences.copyWith(membersSplit: split));

  Future<void> setThemeMode(String mode) =>
      _save(state.preferences.copyWith(themeMode: mode));

  Future<void> setLocale(String locale) =>
      _save(state.preferences.copyWith(locale: locale));
}

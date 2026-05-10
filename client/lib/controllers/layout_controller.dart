import 'package:flutter/foundation.dart';

import '../models/layout_preferences.dart';
import '../repositories/layout_repository.dart';

class LayoutController extends ChangeNotifier {
  LayoutController({LayoutRepository? repository}) : _repository = repository;

  final LayoutRepository? _repository;

  LayoutPreferences _preferences = const LayoutPreferences();
  bool _isLoading = true;

  LayoutPreferences get preferences => _preferences;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _preferences = await _repository?.load() ?? const LayoutPreferences();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setPreset(LayoutPreset preset) {
    return _save(_preferences.copyWith(preset: preset));
  }

  Future<void> setToolPlacement(ToolPanelPlacement placement) {
    return _save(_preferences.copyWith(toolPlacement: placement));
  }

  Future<void> setToolsArrangement(ToolsArrangement arrangement) {
    return _save(_preferences.copyWith(toolsArrangement: arrangement));
  }

  Future<void> setRegionVisibility({
    required bool appRailVisible,
    required bool contextSidebarVisible,
    required bool membersVisible,
    required bool fileTreeVisible,
  }) {
    return _save(
      _preferences.copyWith(
        appRailVisible: appRailVisible,
        contextSidebarVisible: contextSidebarVisible,
        membersVisible: membersVisible,
        fileTreeVisible: fileTreeVisible,
      ),
    );
  }

  Future<void> setRightToolsWidth(double width) {
    return _save(_preferences.copyWith(rightToolsWidth: width));
  }

  Future<void> setBottomToolsHeight(double height) {
    return _save(_preferences.copyWith(bottomToolsHeight: height));
  }

  Future<void> setMembersSplit(double split) {
    return _save(_preferences.copyWith(membersSplit: split));
  }

  Future<void> _save(LayoutPreferences preferences) async {
    _preferences = preferences;
    notifyListeners();
    await _repository?.save(_preferences);
  }
}

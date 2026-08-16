import 'package:flutter/foundation.dart';

/// In-session Edit|Preview mode for html editor paths.
///
/// Survives File↔Diff and tab switches (FileEditorSurface dispose). Not
/// persisted to disk.
class HtmlViewModeStore extends ChangeNotifier {
  HtmlViewModeStore();

  final Map<String, HtmlViewMode> _modes = {};

  HtmlViewMode modeFor(String path) => _modes[path] ?? HtmlViewMode.edit;

  void setMode(String path, HtmlViewMode mode) {
    if (_modes[path] == mode) return;
    _modes[path] = mode;
    notifyListeners();
  }
}

enum HtmlViewMode { edit, preview }

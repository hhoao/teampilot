import 'package:flutter/foundation.dart';

/// In-session Preview|Edit mode for SVG editor paths.
///
/// SVG opens **rendered** by default (unlike [HtmlViewModeStore], which
/// defaults to edit). Survives File↔Diff and tab switches (FileEditorSurface
/// dispose). Not persisted to disk.
class SvgViewModeStore extends ChangeNotifier {
  SvgViewModeStore();

  final Map<String, SvgViewMode> _modes = {};

  SvgViewMode modeFor(String path) => _modes[path] ?? SvgViewMode.preview;

  void setMode(String path, SvgViewMode mode) {
    if (_modes[path] == mode) return;
    _modes[path] = mode;
    notifyListeners();
  }
}

enum SvgViewMode { preview, edit }

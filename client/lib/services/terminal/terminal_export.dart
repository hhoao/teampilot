import 'package:flutter_alacritty/flutter_alacritty.dart';

/// Serializes the visible terminal viewport to plain text.
///
/// Full scrollback export is not yet exposed by the engine; this walks the
/// current [TerminalGridView] mirror for a best-effort export.
String exportTerminalScrollback(TerminalEngine engine) {
  final grid = engine.grid;
  final buffer = StringBuffer();
  for (var row = 0; row < grid.rows; row++) {
    final runes = <int>[];
    for (var col = 0; col < grid.columns; col++) {
      final cp = grid.codepointAt(row, col);
      if (cp == 0) continue;
      runes.add(cp);
    }
    while (runes.isNotEmpty && runes.last == 32) {
      runes.removeLast();
    }
    buffer.writeln(String.fromCharCodes(runes));
  }
  return buffer.toString();
}

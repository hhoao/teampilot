import 'package:xterm/xterm.dart';

/// Serializes terminal scrollback (including wrapped lines) to plain text.
String exportTerminalScrollback(Terminal terminal) {
  return terminal.buffer.getText();
}

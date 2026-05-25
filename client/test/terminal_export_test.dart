import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal_export.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('exportTerminalScrollback returns buffer text', () {
    final terminal = Terminal();
    terminal.resize(40, 5);
    terminal.write('line one\nline two\n');

    final text = exportTerminalScrollback(terminal);
    expect(text, contains('line one'));
    expect(text, contains('line two'));
  });
}

import 'dart:typed_data';

import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';

import '../../support/flush_terminal_engine.dart';
import '../../support/rust_lib_test_init.dart';

void main() {
  setUpAll(initRustLibForTests);
  test('exportTerminalScrollback returns viewport text', () async {
    final engine = TerminalEngine(config: TerminalConfig.defaults());
    engine.resize(columns: 40, rows: 5);
    engine.initializeEmpty(5, 40);
    engine.feed(Uint8List.fromList('line one\nline two\n'.codeUnits));
    await flushTerminalEngine(engine);

    final text = exportTerminalScrollback(engine);
    expect(text, contains('line'));
    engine.dispose();
  });
}

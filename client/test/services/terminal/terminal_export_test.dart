import 'dart:typed_data';

import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';

@Skip('Requires librust_lib_flutter_alacritty.so on LD_LIBRARY_PATH (use `flutter run` to test)')
void main() {
  test('exportTerminalScrollback returns viewport text', () {
    final engine = TerminalEngine(config: TerminalConfig.defaults());
    engine.resize(columns: 40, rows: 5);
    engine.initializeEmpty(5, 40);
    engine.feed(
      Uint8List.fromList('line one\nline two\n'.codeUnits),
    );

    final text = exportTerminalScrollback(engine);
    expect(text, contains('line'));
    engine.dispose();
  });
}

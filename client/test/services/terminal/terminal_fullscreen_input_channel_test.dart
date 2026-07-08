import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_fullscreen_input_channel.dart';

void main() {
  test('submitFullScreenInput writes bracketed paste then a standalone CR', () async {
    final writes = <String>[];
    final channel = TerminalFullscreenInputChannel(writeToPty: writes.add);

    await channel.submitFullScreenInput(
      'hello team',
      defaultSettleDelay: Duration.zero,
      onTurnStart: () {},
    );

    expect(writes, ['\x1B[200~hello team\x1B[201~', '\r']);
  });

  test('writeln writes text and CR as a single chunk', () {
    final writes = <String>[];
    final channel = TerminalFullscreenInputChannel(writeToPty: writes.add);

    channel.writeln('hello team', onTurnStart: () {});

    expect(writes, ['hello team\r']);
  });
}

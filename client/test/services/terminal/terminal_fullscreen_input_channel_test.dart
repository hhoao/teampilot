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

  test('pasteText chunks large bracketed paste payloads', () async {
    final writes = <String>[];
    final channel = TerminalFullscreenInputChannel(writeToPty: writes.add);
    final body = 'x' * (TerminalFullscreenInputChannel.ptyWriteChunkChars + 50);

    await channel.pasteText(body);

    expect(writes.length, greaterThan(1));
    expect(writes.first, startsWith('\x1B[200~'));
    expect(writes.last, endsWith('\x1B[201~'));
    expect(writes.join(), '\x1B[200~$body\x1B[201~');
  });

  test('writeln writes text and CR as a single chunk', () async {
    final writes = <String>[];
    final channel = TerminalFullscreenInputChannel(writeToPty: writes.add);

    channel.writeln('hello team', onTurnStart: () {});
    await Future<void>.delayed(Duration.zero);

    expect(writes, ['hello team\r']);
  });
}

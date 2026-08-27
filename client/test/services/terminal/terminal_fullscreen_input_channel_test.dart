import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_fullscreen_input_channel.dart';
import 'package:teampilot/services/terminal/terminal_input_command_queue.dart';

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

  test('confirmation before queued CR drops it in the production channel',
      () async {
    final writes = <String>[];
    var confirmed = false;
    final commands = TerminalInputCommandQueue(write: writes.add);
    final channel = TerminalFullscreenInputChannel(commands: commands);

    await channel.submitPendingCr(canExecute: () => true);
    final queuedCr = channel.submitPendingCr(
      canExecute: () => !confirmed,
    );
    confirmed = true;
    await queuedCr;

    expect(writes.where((write) => write == '\r'), hasLength(1));
  });

  test('confirmation during staged clear fences every later Ctrl-U', () async {
    final writes = <String>[];
    var confirmed = false;
    final channel = TerminalFullscreenInputChannel(
      writeToPty: (write) {
        writes.add(write);
        if (write == '\x15') confirmed = true;
      },
    );

    await channel.clearStagedInput(
      canExecute: () => !confirmed,
      killLines: 3,
    );

    expect(writes.where((write) => write == '\x15'), hasLength(1));
  });

  test('confirmation before queued staged clear drops every Ctrl-U', () async {
    final writes = <String>[];
    var confirmed = false;
    final channel = TerminalFullscreenInputChannel(writeToPty: writes.add);

    final clear = channel.clearStagedInput(
      canExecute: () => !confirmed,
      killLines: 3,
    );
    confirmed = true;
    await clear;

    expect(writes.where((write) => write == '\x15'), isEmpty);
  });
}

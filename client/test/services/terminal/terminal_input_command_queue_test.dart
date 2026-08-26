import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_input_command_queue.dart';

void main() {
  test('confirmation before queued CR execution drops that CR', () async {
    final writes = <String>[];
    var confirmed = false;
    final queue = TerminalInputCommandQueue(write: writes.add);

    await queue.enqueue(
      TerminalInputCommand.bytes('paste', canExecute: () => true),
    );
    final queuedCr = queue.enqueue(
      TerminalInputCommand.bytes('\r', canExecute: () => !confirmed),
    );
    confirmed = true;

    expect(await queuedCr, TerminalInputCommandResult.dropped);
    expect(writes, ['paste']);
  });
}

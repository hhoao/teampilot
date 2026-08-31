import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/process_exit_failure_message.dart';

void main() {
  test('composeProcessExitFailureMessage keeps exit stub alone when no output', () {
    expect(
      composeProcessExitFailureMessage(code: 1),
      '[process exited with code 1]',
    );
    expect(
      composeProcessExitFailureMessage(code: 1, duringStartup: true),
      '[process exited with code 1 during startup]',
    );
    expect(
      composeProcessExitFailureMessage(code: 0, duringStartup: true),
      '[process exited unexpectedly during startup]',
    );
  });

  test('composeProcessExitFailureMessage prepends recent PTY text', () {
    const output =
        'Error: [unavailable] connect ETIMEDOUT 28.0.0.8:443';
    expect(
      composeProcessExitFailureMessage(code: 1, recentOutput: output),
      '$output\n\n[process exited with code 1]',
    );
  });

  test('composeProcessExitFailureMessage strips ANSI from recent output', () {
    const output = '\x1B[31mError: boom\x1B[0m';
    expect(
      composeProcessExitFailureMessage(code: 1, recentOutput: output),
      'Error: boom\n\n[process exited with code 1]',
    );
  });

  test('composeProcessExitFailureMessage soft-caps extremely long output', () {
    final output = 'x' * (kProcessExitFailureOutputMaxChars + 40);
    final composed = composeProcessExitFailureMessage(
      code: 1,
      recentOutput: output,
    );
    expect(composed.startsWith('…'), isTrue);
    expect(composed, endsWith('[process exited with code 1]'));
    expect(
      composed.length,
      lessThan(output.length + 80),
    );
  });
}

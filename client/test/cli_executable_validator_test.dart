import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli_executable_validator.dart';

void main() {
  test('returns null for bare executable name on PATH', () {
    final which = Process.runSync('which', ['true']);
    if (which.exitCode != 0) return;

    expect(
      CliExecutableValidator.validateLaunch(
        executable: 'true',
        workingDirectory: Directory.current.path,
      ),
      isNull,
    );
  });

  test('reports bare name missing from PATH', () {
    final message = CliExecutableValidator.validateLaunch(
      executable: 'teampilot-definitely-missing-cli-name',
      workingDirectory: Directory.current.path,
    );
    expect(message, isNotNull);
    expect(message, contains('not found on PATH'));
  });

  test('reports missing absolute executable path', () {
    final message = CliExecutableValidator.validateLaunch(
      executable: '/tmp/teampilot-missing-flashskyai-executable',
      workingDirectory: Directory.current.path,
    );
    expect(message, isNotNull);
    expect(message, contains('not found'));
    expect(message, contains('/tmp/teampilot-missing-flashskyai-executable'));
  });

  test('reports missing working directory', () {
    final message = CliExecutableValidator.validateLaunch(
      executable: 'flashskyai',
      workingDirectory: '/tmp/teampilot-missing-working-directory',
    );
    expect(message, isNotNull);
    expect(message, contains('Working directory does not exist'));
  });
}

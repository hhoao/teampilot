import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/shell_script_configuration.dart';

void main() {
  test('missingOnLocalHost ignores empty and bare names', () {
    expect(ShellScriptConfiguration.missingOnLocalHost(''), isFalse);
    expect(ShellScriptConfiguration.missingOnLocalHost('bash'), isFalse);
    expect(ShellScriptConfiguration.missingOnLocalHost('python3'), isFalse);
  });

  test('missingOnLocalHost detects path-like missing executables', () {
    expect(
      ShellScriptConfiguration.missingOnLocalHost(
        '/definitely/not/a/real/shell',
      ),
      isTrue,
    );
  });
}

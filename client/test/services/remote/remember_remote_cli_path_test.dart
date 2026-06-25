import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/remote/remote_member_preflight_factory.dart';

void main() {
  test('persists newly resolved path', () async {
    final writes = <(String, String, String)>[];
    await rememberRemoteCliPathIfNeeded(
      targetId: 'ssh:work',
      cli: CliTool.claude,
      resolvedPath: '/home/dev/.local/bin/claude',
      readCliPathOverride: (_, __) async => null,
      writeCliPathOverride: (targetId, cliValue, path) async {
        writes.add((targetId, cliValue, path));
      },
    );
    expect(
      writes,
      [('ssh:work', 'claude', '/home/dev/.local/bin/claude')],
    );
  });

  test('skips write when path matches stored override', () async {
    var writeCount = 0;
    await rememberRemoteCliPathIfNeeded(
      targetId: 'ssh:work',
      cli: CliTool.claude,
      resolvedPath: '/custom/claude',
      readCliPathOverride: (_, __) async => '/custom/claude',
      writeCliPathOverride: (_, __, ___) async => writeCount++,
    );
    expect(writeCount, 0);
  });

  test('ignores empty resolved path', () async {
    var writeCount = 0;
    await rememberRemoteCliPathIfNeeded(
      targetId: 'ssh:work',
      cli: CliTool.claude,
      resolvedPath: '  ',
      readCliPathOverride: (_, __) async => null,
      writeCliPathOverride: (_, __, ___) async => writeCount++,
    );
    expect(writeCount, 0);
  });
}

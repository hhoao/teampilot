import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';

void main() {
  test('HeadlessRunContext exposes its fields verbatim', () {
    const ctx = HeadlessRunContext(
      prompt: 'hi',
      model: 'sonnet',
      effort: 'high',
      configDir: '/tmp/cfg',
      workingDirectory: '/repo',
      expectJson: true,
    );
    expect(ctx.prompt, 'hi');
    expect(ctx.model, 'sonnet');
    expect(ctx.effort, 'high');
    expect(ctx.configDir, '/tmp/cfg');
    expect(ctx.workingDirectory, '/repo');
    expect(ctx.expectJson, isTrue);
  });

  test('HeadlessInvocation defaults environment to empty', () {
    const inv = HeadlessInvocation(executable: 'claude', arguments: ['-p', 'x']);
    expect(inv.executable, 'claude');
    expect(inv.arguments, ['-p', 'x']);
    expect(inv.environment, isEmpty);
  });

  test('HeadlessConfigFile holds relative path and contents', () {
    const f = HeadlessConfigFile(relativePath: 'settings.json', contents: '{}');
    expect(f.relativePath, 'settings.json');
    expect(f.contents, '{}');
  });
}

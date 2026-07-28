import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/skill/acquire/skill_acquire_context.dart';

void main() {
  test('resolveRelative stays under sync root', () {
    final ctx = SkillAcquireContext(overwrite: false, expectedSkillId: 'x')
      ..syncRoot = '/tmp/sync';
    expect(ctx.resolveRelative('bin'), '/tmp/sync/bin');
    expect(() => ctx.resolveRelative('/etc/passwd'), throwsA(isA<StateError>()));
    expect(() => ctx.resolveRelative('../outside'), throwsA(isA<StateError>()));
  });

  test('WORKDIR affects resolveWorkdirRelative', () {
    final ctx = SkillAcquireContext(overwrite: false, expectedSkillId: 'x')
      ..syncRoot = '/tmp/sync'
      ..workdir = 'nested';
    expect(ctx.resolveWorkdirRelative('out.txt'), '/tmp/sync/nested/out.txt');
  });
}

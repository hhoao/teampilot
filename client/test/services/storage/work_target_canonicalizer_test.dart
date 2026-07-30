import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/work_target_canonicalizer.dart';

void main() {
  final sshHome = RuntimeTarget.ssh('p1', label: 'box');
  final wslHome = RuntimeTarget.wsl('Ubuntu');
  final localHome = RuntimeTarget.local();
  final termuxHome = RuntimeTarget.termux();

  test('defaultFolderTargetId follows home kind', () {
    expect(WorkTargetCanonicalizer.defaultFolderTargetId(localHome), 'local');
    expect(WorkTargetCanonicalizer.defaultFolderTargetId(sshHome), 'ssh:p1');
    expect(WorkTargetCanonicalizer.defaultFolderTargetId(wslHome), 'wsl:Ubuntu');
  });

  test('resolve keeps local when home is local', () {
    expect(
      WorkTargetCanonicalizer.resolve('local', home: localHome).id,
      'local',
    );
  });

  test('resolve rewrites local to non-local home', () {
    expect(
      WorkTargetCanonicalizer.resolve('local', home: sshHome),
      sshHome,
    );
    expect(
      WorkTargetCanonicalizer.resolve('local', home: wslHome),
      wslHome,
    );
  });

  test('resolve leaves explicit ssh/wsl ids unchanged', () {
    expect(
      WorkTargetCanonicalizer.resolve('ssh:other', home: sshHome).id,
      'ssh:other',
    );
    expect(
      WorkTargetCanonicalizer.resolve('wsl:Other', home: wslHome).id,
      'wsl:Other',
    );
  });

  test('fromId parses bare ids without home rewrite', () {
    expect(WorkTargetCanonicalizer.fromId('local').kind, RuntimeKind.local);
    expect(WorkTargetCanonicalizer.fromId('ssh:p1').sshProfileId, 'p1');
  });

  test('defaultFolderTargetId for termux home', () {
    expect(
      WorkTargetCanonicalizer.defaultFolderTargetId(termuxHome),
      'termux:default',
    );
  });

  test('bare local resolves to termux home', () {
    expect(
      WorkTargetCanonicalizer.resolve('local', home: termuxHome),
      termuxHome,
    );
  });

  test('fromId parses termux', () {
    expect(
      WorkTargetCanonicalizer.fromId('termux:default').kind,
      RuntimeKind.termux,
    );
    expect(
      WorkTargetCanonicalizer.fromId('termux:default').sshProfileId,
      'termux',
    );
  });
}

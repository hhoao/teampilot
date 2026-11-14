import 'dart:convert';
import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test(
    'spools updates, bounds the memory tail, and keeps env out of jsonl',
    () async {
      final root = await Directory.systemTemp.createTemp('acp-proxy-spool');
      addTearDown(() => root.delete(recursive: true));

      const executable = '/usr/local/bin/claude';
      final meta = AcpProxyLaunchMeta(
        cli: 'claude',
        executable: executable,
        args: const ['--acp'],
        env: const {'TOKEN': 'super-secret'},
        permissionPolicy: AcpProxyPermissionPolicy.fullAccess,
      );

      final updates = <Map<String, Object?>>[
        {'n': 1},
        {'n': 2},
        {'n': 3},
      ];
      // Twice the JSON size still fits two objects when newlines are ignored.
      // Each jsonl line includes a newline, so this budget keeps only the last.
      final oneJson = utf8.encode(jsonEncode(updates.last)).length;
      final spool = AcpProxySpool(root: root, memoryTailBytes: oneJson * 2);

      await spool.create(sessionId: 's1', cwd: '/work', meta: meta);
      for (final update in updates) {
        spool.appendUpdate('s1', update);
      }

      expect(await spool.readAll('s1'), updates);
      expect(spool.memoryTail('s1'), hasLength(1));
      expect(spool.memoryTail('s1'), [updates.last]);

      final sessionDir = Directory('${root.path}/acp-proxy/sessions/s1');
      final metaFile = File('${sessionDir.path}/meta.json');
      final updatesFile = File('${sessionDir.path}/updates.jsonl');
      final metaText = await metaFile.readAsString();
      expect(metaText, contains('executable'));
      expect(metaText, contains(executable));
      expect(metaText, contains('super-secret'));

      final updatesText = await updatesFile.readAsString();
      expect(updatesText, isNot(contains('super-secret')));
      expect(updatesText, endsWith('\n'));

      if (!Platform.isWindows) {
        expect((await sessionDir.stat()).mode & 0x1ff, 0x1c0);
        expect((await metaFile.stat()).mode & 0x1ff, 0x180);
        expect((await updatesFile.stat()).mode & 0x1ff, 0x180);
      }

      await spool.delete('s1');
      expect(sessionDir.existsSync(), isFalse);
    },
  );

  test('rejects session ids that are not one path segment', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-spool');
    addTearDown(() => root.delete(recursive: true));
    final spool = AcpProxySpool(root: root);
    final outside = Directory('${root.path}/acp-proxy/outside');
    await outside.create(recursive: true);
    const meta = AcpProxyLaunchMeta(
      cli: 'claude',
      executable: '/usr/local/bin/claude',
      args: ['--acp'],
      env: {'TOKEN': 'super-secret'},
      permissionPolicy: AcpProxyPermissionPolicy.ask,
    );

    for (final id in ['../outside', '..', '.', '', 'a/b', r'a\b', 'foo..bar']) {
      await expectLater(
        spool.create(sessionId: id, cwd: '/work', meta: meta),
        throwsFormatException,
      );
      expect(() => spool.appendUpdate(id, {'n': 1}), throwsFormatException);
      await expectLater(spool.readAll(id), throwsFormatException);
      await expectLater(spool.delete(id), throwsFormatException);
    }

    expect(outside.existsSync(), isTrue);
    expect(File('${outside.path}/meta.json').existsSync(), isFalse);
    expect(
      Directory('${root.path}/acp-proxy/sessions/a').existsSync(),
      isFalse,
    );
  });

  test(
    'create removes the session directory when writing the spool fails',
    () async {
      final root = await Directory.systemTemp.createTemp('acp-proxy-spool');
      addTearDown(() => root.delete(recursive: true));
      final spool = AcpProxySpool(root: root);
      final session = Directory('${root.path}/acp-proxy/sessions/s1');
      await Directory('${session.path}/meta.json').create(recursive: true);

      await expectLater(
        spool.create(
          sessionId: 's1',
          cwd: '/work',
          meta: const AcpProxyLaunchMeta(
            cli: 'claude',
            executable: '/usr/local/bin/claude',
            args: ['--acp'],
            env: {},
            permissionPolicy: AcpProxyPermissionPolicy.ask,
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(session.existsSync(), isFalse);
    },
  );
}

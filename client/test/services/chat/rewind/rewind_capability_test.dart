import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/chat/rewind/rewind_capability.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../../support/test_git_command_runner.dart';

/// Fake git runner with an overridable, counted `probe()` (controller Gap 2).
class _ProbeRunner extends TestGitCommandRunner {
  _ProbeRunner(this.capability, this.onProbe);

  final GitCapability capability;
  final void Function() onProbe;

  @override
  Future<GitCapability> probe() async {
    onProbe();
    return capability;
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('capability-');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  RuntimeContext ctx(RuntimeTarget target) => RuntimeContext(
    target: target,
    filesystem: LocalFilesystem(),
    home: dir.path,
    cwd: dir.path,
    appDataRoot: dir.path,
    paths: AppPaths(dir.path),
  );

  RuntimeTarget target(String id) =>
      RuntimeTarget(id: id, label: id);

  const capable = GitCapability(
    available: true,
    version: '2.43',
    pathspecFromFile: true,
  );

  test('forContext calls probe() exactly once for repeated calls on same target',
      () async {
    var probes = 0;
    final cache = RewindCapabilityCache(
      runnerFor: (_) => _ProbeRunner(capable, () => probes++),
    );
    final c = ctx(target('local'));
    await cache.forContext(c);
    await cache.forContext(c);
    await cache.forContext(c);
    expect(probes, 1);
  });

  test('peek is null before forContext and equals the capability after',
      () async {
    var probes = 0;
    final cache = RewindCapabilityCache(
      runnerFor: (_) => _ProbeRunner(capable, () => probes++),
    );
    final t = target('local');
    expect(cache.peek(t.id), isNull);
    final cap = await cache.forContext(ctx(t));
    final peeked = cache.peek(t.id);
    expect(peeked, isNotNull);
    expect(peeked!.available, cap.available);
    expect(peeked.version, cap.version);
    expect(peeked.pathspecFromFile, cap.pathspecFromFile);
  });

  test('available / version / pathspecFromFile are passed through', () async {
    final cache = RewindCapabilityCache(
      runnerFor: (_) => _ProbeRunner(capable, () {}),
    );
    final cap = await cache.forContext(ctx(target('local')));
    expect(cap.available, isTrue);
    expect(cap.version, '2.43');
    expect(cap.pathspecFromFile, isTrue);
  });

  test('GitCapability.unavailable yields RewindCapability.available == false',
      () async {
    final cache = RewindCapabilityCache(
      runnerFor: (_) => _ProbeRunner(GitCapability.unavailable, () {}),
    );
    final cap = await cache.forContext(ctx(target('local')));
    expect(cap.available, isFalse);
    expect(cache.peek('local'), isNotNull);
    expect(cache.peek('local')!.available, isFalse);
  });

  test('invalidate forces one new probe; clear forces new probes for all',
      () async {
    var probes = 0;
    final cache = RewindCapabilityCache(
      runnerFor: (_) => _ProbeRunner(capable, () => probes++),
    );
    final a = target('a');
    final b = target('b');
    await cache.forContext(ctx(a));
    await cache.forContext(ctx(b));
    expect(probes, 2);

    cache.invalidate(a.id);
    await cache.forContext(ctx(a));
    expect(probes, 3);
    await cache.forContext(ctx(b));
    expect(probes, 3); // b is still cached

    cache.clear();
    await cache.forContext(ctx(a));
    await cache.forContext(ctx(b));
    expect(probes, 5);
  });

  test('two different target ids are cached independently (two probes)',
      () async {
    var probes = 0;
    final cache = RewindCapabilityCache(
      runnerFor: (_) => _ProbeRunner(capable, () => probes++),
    );
    await cache.forContext(ctx(target('a')));
    await cache.forContext(ctx(target('b')));
    expect(probes, 2);
    expect(cache.peek('a'), isNotNull);
    expect(cache.peek('b'), isNotNull);
  });
}

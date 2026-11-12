import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/chat/rewind/seat_runtime_resolver.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('resolver-');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  // Local helper (controller Gap 1): captures the temp dir so the brief's
  // `ctx(target)` one-arg call works while still allowing distinct target ids.
  RuntimeContext ctx(RuntimeTarget target) => RuntimeContext(
    target: target,
    filesystem: LocalFilesystem(),
    home: dir.path,
    cwd: dir.path,
    appDataRoot: dir.path,
    paths: AppPaths(dir.path),
  );

  test('caches by target id and invalidates', () async {
    var calls = 0;
    final resolver = SeatRuntimeResolver(
      resolve: (target) async {
        calls++;
        return ctx(target);
      },
    );
    const target = RuntimeTarget(
      id: 'ssh:p',
      label: 'p',
      kind: RuntimeKind.ssh,
    );
    await resolver.forTarget(target);
    await resolver.forTarget(target);
    expect(calls, 1);
    resolver.invalidate(target.id);
    await resolver.forTarget(target);
    expect(calls, 2);
  });

  test('peek is null before resolve and returns the cached context after',
      () async {
    final resolver = SeatRuntimeResolver(
      resolve: (target) async => ctx(target),
    );
    const target = RuntimeTarget(
      id: 'local',
      label: 'local',
      kind: RuntimeKind.local,
    );
    expect(resolver.peek(target.id), isNull);
    final resolved = await resolver.forTarget(target);
    expect(resolver.peek(target.id), same(resolved));
  });

  test('clear forces re-resolve for all cached targets', () async {
    var calls = 0;
    final resolver = SeatRuntimeResolver(
      resolve: (target) async {
        calls++;
        return ctx(target);
      },
    );
    const a = RuntimeTarget(id: 'ssh:a', label: 'a', kind: RuntimeKind.ssh);
    const b = RuntimeTarget(id: 'ssh:b', label: 'b', kind: RuntimeKind.ssh);
    await resolver.forTarget(a);
    await resolver.forTarget(b);
    expect(calls, 2);
    resolver.clear();
    expect(resolver.peek(a.id), isNull);
    await resolver.forTarget(a);
    await resolver.forTarget(b);
    expect(calls, 4);
  });

  test('distinct target ids resolve independently', () async {
    var calls = 0;
    final resolver = SeatRuntimeResolver(
      resolve: (target) async {
        calls++;
        return ctx(target);
      },
    );
    const a = RuntimeTarget(id: 'ssh:a', label: 'a', kind: RuntimeKind.ssh);
    const b = RuntimeTarget(id: 'ssh:b', label: 'b', kind: RuntimeKind.ssh);
    final ca = await resolver.forTarget(a);
    final cb = await resolver.forTarget(b);
    expect(calls, 2);
    expect(ca.target.id, 'ssh:a');
    expect(cb.target.id, 'ssh:b');
    expect(resolver.peek(a.id), same(ca));
    expect(resolver.peek(b.id), same(cb));
  });
}

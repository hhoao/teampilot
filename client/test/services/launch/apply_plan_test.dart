import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/launch/apply_plan.dart';

void main() {
  final ctx = p.Context(style: p.Style.posix);

  test('json roundtrip keeps protocolVersion 1 and op order', () {
    final plan = ApplyPlan(
      workRoot: '/work',
      ops: [
        ApplyEnsureDir('/work/a'),
        ApplyWriteInline(path: '/work/a/f.txt', content: 'hi'),
        ApplyWriteBlob(path: '/work/a/b.bin', sha256: 'ab' * 32),
        ApplyTree(
          dest: '/work/t',
          entries: [ApplyTreeEntry(rel: 'x', sha256: 'cd' * 32)],
        ),
        ApplySymlink(linkPath: '/work/l', target: '/work/t'),
        ApplyRemove('/work/old'),
        ApplyRename(from: '/work/a', to: '/work/b'),
      ],
    );
    final decoded = ApplyPlan.fromJson(plan.toJson());
    expect(decoded.protocolVersion, applyPlanProtocolVersion);
    expect(decoded.workRoot, '/work');
    expect(decoded.ops, hasLength(7));
    expect(decoded.ops[0], isA<ApplyEnsureDir>());
    expect(decoded.ops[4], isA<ApplySymlink>());
  });

  test('sandbox rejects path escape and NUL', () {
    expect(
      () => assertApplyPath(
        path: '/work/../etc/passwd',
        workRoot: '/work',
        pathContext: ctx,
      ),
      throwsStateError,
    );
    expect(
      () => assertApplyPath(
        path: '/work/a\x00b',
        workRoot: '/work',
        pathContext: ctx,
      ),
      throwsStateError,
    );
    expect(
      () => assertApplyPath(
        path: '/etc/passwd',
        workRoot: '/work',
        pathContext: ctx,
      ),
      throwsStateError,
    );
    assertApplyPath(path: '/work', workRoot: '/work', pathContext: ctx);
    assertApplyPath(path: '/work/a/b', workRoot: '/work', pathContext: ctx);
  });

  test('utf8 writeFile threshold is 4096', () {
    expect(utf8.encode('a' * applyPlanInlineLimitBytes).length, 4096);
  });
}

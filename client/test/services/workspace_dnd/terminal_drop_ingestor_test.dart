import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_behavior_capability.dart';
import 'package:teampilot/services/workspace_dnd/cross_namespace_strategy.dart';
import 'package:teampilot/services/workspace_dnd/path_namespace.dart';
import 'package:teampilot/services/workspace_dnd/path_projection.dart';
import 'package:teampilot/services/workspace_dnd/path_reference_formatter.dart';
import 'package:teampilot/services/workspace_dnd/runtime_target.dart';
import 'package:teampilot/services/workspace_dnd/terminal_drop_ingestor.dart';
import 'package:teampilot/services/workspace_dnd/terminal_text_sink.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';

class _FakeSink implements TerminalTextSink {
  final List<String> appended = [];
  final List<String> pasted = [];

  @override
  void appendText(String text) => appended.add(text);

  @override
  Future<void> pasteWithoutSubmit(String text) async => pasted.add(text);
}

/// A cross-namespace strategy that "uploads" by returning a fixed remote path,
/// used to prove the ingestor delivers a resolved cross-namespace path.
class _StubUploadStrategy implements CrossNamespaceStrategy {
  const _StubUploadStrategy(this.remotePath);
  final String remotePath;
  @override
  Future<String?> resolve(CrossNamespacePath path) async => remotePath;
}

WorkspaceDragPayload _payload(List<String> paths, PathNamespace ns) {
  return WorkspaceDragPayload(
    kind: DragPayloadKind.workspaceFile,
    refs: [
      for (final p in paths)
        WorkspaceFileRef(nativePath: p, namespace: ns, isDirectory: false),
    ],
  );
}

void main() {
  TerminalDropIngestor ingestor(
    _FakeSink sink, {
    required RuntimeTarget target,
    required TerminalPathDropBehavior behavior,
    CrossNamespaceStrategy? strategy,
  }) => TerminalDropIngestor(
    sink: sink,
    target: target,
    behavior: behavior,
    crossNamespaceStrategy:
        strategy ?? const RejectCrossNamespaceStrategy(),
  );

  test('rawAppend writes a trailing-spaced path straight to the PTY', () async {
    final sink = _FakeSink();
    final outcome = await ingestor(
      sink,
      target: const RuntimeTarget.localPosix(),
      behavior: TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false),
    ).consume(_payload(['/repo/x.dart'], const PathNamespace.localPosix()));

    expect(sink.appended, ['/repo/x.dart ']);
    expect(sink.pasted, isEmpty);
    expect(outcome.delivered, 1);
    expect(outcome.anyRejected, isFalse);
  });

  test('bracketedNoSubmit pastes without submitting for full-screen TUIs', () async {
    final sink = _FakeSink();
    await ingestor(
      sink,
      target: const RuntimeTarget.localPosix(),
      behavior: TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true),
    ).consume(_payload(['/repo/x.dart'], const PathNamespace.localPosix()));

    expect(sink.pasted, ['/repo/x.dart ']);
    expect(sink.appended, isEmpty);
  });

  test('multiple paths are quoted and space-joined in one delivery', () async {
    final sink = _FakeSink();
    final outcome = await ingestor(
      sink,
      target: const RuntimeTarget.localPosix(),
      behavior: TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false),
    ).consume(
      _payload(
        ['/repo/a.dart', '/repo/my file.txt'],
        const PathNamespace.localPosix(),
      ),
    );

    expect(sink.appended, [r"/repo/a.dart '/repo/my file.txt' "]);
    expect(outcome.delivered, 2);
  });

  test('cross-namespace paths are rejected and nothing is written by default', () async {
    final sink = _FakeSink();
    final outcome = await ingestor(
      sink,
      target: const RuntimeTarget.ssh(),
      behavior: TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false),
    ).consume(_payload(['/repo/x.dart'], const PathNamespace.localPosix()));

    expect(sink.appended, isEmpty);
    expect(outcome.delivered, 0);
    expect(outcome.rejectedCrossNamespace, 1);
  });

  test('a cross-namespace strategy can resolve a deliverable remote path', () async {
    final sink = _FakeSink();
    final outcome = await ingestor(
      sink,
      target: const RuntimeTarget.ssh(),
      behavior: TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false),
      strategy: const _StubUploadStrategy('/remote/uploads/x.dart'),
    ).consume(_payload(['/repo/x.dart'], const PathNamespace.localPosix()));

    expect(sink.appended, ['/remote/uploads/x.dart ']);
    expect(outcome.delivered, 1);
    expect(outcome.rejectedCrossNamespace, 0);
  });

  test('quoting follows the behavior PathQuoting (none leaves spaces raw)', () async {
    final sink = _FakeSink();
    await ingestor(
      sink,
      target: const RuntimeTarget.localPosix(),
      behavior: const TerminalPathDropBehavior(
        mode: TerminalPathDropMode.rawAppend,
        quoting: PathQuoting.none,
      ),
    ).consume(_payload(['/repo/my file.txt'], const PathNamespace.localPosix()));

    expect(sink.appended, ['/repo/my file.txt ']);
  });
}

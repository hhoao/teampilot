import '../cli/registry/capabilities/terminal_behavior_capability.dart';
import 'cross_namespace_strategy.dart';
import 'path_projection.dart';
import 'path_reference_formatter.dart';
import 'runtime_target.dart';
import 'terminal_text_sink.dart';
import 'workspace_drop_target.dart';
import 'workspace_file_ref.dart';

/// The terminal as a [WorkspaceDropTarget]: projects each dragged path into the
/// terminal's namespace, quotes it per the CLI's behavior, and injects the
/// result into the input box. The single place the six drag-and-drop concerns
/// (payload → projection → cross-namespace → quoting → paste-mode → sink) meet.
///
/// Built fresh per drop from the active session + its CLI capability. Holds no
/// PTY itself — everything flows through the injected [TerminalTextSink], so it
/// is exercised in tests with a fake sink and no terminal.
class TerminalDropIngestor implements WorkspaceDropTarget {
  TerminalDropIngestor({
    required this.sink,
    required this.target,
    required this.behavior,
    this.projection = const PathProjection(),
    this.formatter = const PathReferenceFormatter(),
    this.crossNamespaceStrategy = const RejectCrossNamespaceStrategy(),
  });

  final TerminalTextSink sink;
  final RuntimeTarget target;
  final TerminalPathDropBehavior behavior;
  final PathProjection projection;
  final PathReferenceFormatter formatter;
  final CrossNamespaceStrategy crossNamespaceStrategy;

  @override
  bool accepts(DragPayloadKind kind) => kind == DragPayloadKind.workspaceFile;

  @override
  Future<DropOutcome> consume(WorkspaceDragPayload payload) async {
    if (!accepts(payload.kind) || payload.isEmpty) return DropOutcome.empty;

    final tokens = <String>[];
    var rejected = 0;
    for (final ref in payload.refs) {
      final path = await _resolvePath(ref);
      if (path == null) {
        rejected += 1;
        continue;
      }
      tokens.add(formatter.format(path, behavior.quoting));
    }
    if (tokens.isEmpty) {
      return DropOutcome(rejectedCrossNamespace: rejected);
    }

    // Trailing space leaves the cursor ready for the next token / prompt text,
    // matching how a path completion behaves when typed.
    final text = '${tokens.join(' ')} ';
    await _deliver(text);
    return DropOutcome(delivered: tokens.length, rejectedCrossNamespace: rejected);
  }

  Future<String?> _resolvePath(WorkspaceFileRef ref) async {
    final result = projection.project(ref, target);
    switch (result) {
      case ProjectedPath(:final projectedPath):
        return projectedPath;
      case CrossNamespacePath():
        return crossNamespaceStrategy.resolve(result);
    }
  }

  Future<void> _deliver(String text) async {
    switch (behavior.mode) {
      case TerminalPathDropMode.rawAppend:
        sink.appendText(text);
      case TerminalPathDropMode.bracketedNoSubmit:
        await sink.pasteWithoutSubmit(text);
    }
  }
}

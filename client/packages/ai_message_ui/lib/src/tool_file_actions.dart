import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'default_tool_resolvers.dart';
import 'edit/edit_line_highlighter.dart';

/// Host-injected resolvers + open handler for tool-call targets.
@immutable
class AiToolFileActions {
  const AiToolFileActions({
    required this.fileResolver,
    required this.editResolver,
    required this.shellResolver,
    this.onOpenFile,
    this.lineHighlighter = const PlainEditLineHighlighter(),
  });

  final AiToolFileTargetResolver fileResolver;
  final AiEditToolTargetResolver editResolver;
  final AiShellToolTargetResolver shellResolver;
  final Future<void> Function(AiToolFileTarget target)? onOpenFile;
  final AiEditLineHighlighter lineHighlighter;

  /// Without a scope the package falls back to its built-in file resolver so
  /// read/write summary chrome still renders; edit and shell targets stay
  /// host-owned.
  static const _fallback = AiToolFileActions(
    fileResolver: DefaultAiToolFileTargetResolver(),
    editResolver: NoopEditToolTargetResolver(),
    shellResolver: DefaultAiShellToolTargetResolver(),
  );

  static AiToolFileActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiToolFileActionsScope>()
            ?.actions ??
        _fallback;
  }
}

/// Debug-only counters for [AiToolFileActionsScope].
///
/// `republish` counts how often a new instance had to be published (each one
/// dirties every chain-of-thought block and tool card).
class AiToolFileActionsScopeStats {
  int stateCreations = 0;
  int republishes = 0;

  @override
  String toString() =>
      'toolActions states=$stateCreations republish=$republishes';
}

final AiToolFileActionsScopeStats aiToolFileActionsScopeStats =
    AiToolFileActionsScopeStats();

/// Key on the resolver *implementation*, not on the instance.
///
/// Hosts rebuild [AiToolFileActions] on every pass; several of those fields are
/// recreated objects even when nothing about their behaviour changed. Identity
/// keys therefore thrash, publishing a new object each time and dirtying every
/// dependent. [AiToolFileActionsScope.scopeId] keeps sessions with the same CLI
/// from sharing one published callback (a tool-file tap must open in its seat).
typedef _ActionsShape = (Object?, Type, Type, Type, Type, bool);

_ActionsShape _shapeOf(AiToolFileActions a, Object? scopeId) => (
  scopeId,
  a.fileResolver.runtimeType,
  a.editResolver.runtimeType,
  a.shellResolver.runtimeType,
  a.lineHighlighter.runtimeType,
  a.onOpenFile == null,
);

/// One stable [AiToolFileActions] per resolver shape, held outside the scope's
/// [State].
///
/// The message area is rebuilt routinely while the transcript keeps its
/// elements (the viewport keys turns with `GlobalKey`). That recreates the
/// scope's element but not its descendants, so any cache held in [State] would
/// be thrown away and hand the descendants a brand-new actions object — which
/// dirties every chain-of-thought header. A process-wide cache keyed on the
/// resolvers survives the remount.
final Map<_ActionsShape, _PublishedActions> _publishedActionsByShape = {};

class _PublishedActions {
  _PublishedActions(AiToolFileActions first) : _latest = first {
    value = AiToolFileActions(
      fileResolver: first.fileResolver,
      editResolver: first.editResolver,
      shellResolver: first.shellResolver,
      lineHighlighter: first.lineHighlighter,
      // Hosts recreate the closure on every build; resolve through the newest
      // one each time so the tap still reaches the live host callback.
      onOpenFile: first.onOpenFile == null
          ? null
          : (target) async {
              final callback = _latest?.onOpenFile;
              if (callback != null) await callback(target);
            },
    );
  }

  AiToolFileActions? _latest;
  late final AiToolFileActions value;
  final Set<Object> _owners = {};

  bool get hasOwners => _owners.isNotEmpty;

  void attach(Object owner, AiToolFileActions next) {
    _owners.add(owner);
    _latest = next;
  }

  /// Drops the retained host callback once no live scope needs it. The entry
  /// itself stays, so a remount still finds the same instance; only the closure
  /// (which captures a `BuildContext` and its whole element subtree) is
  /// released, letting a closed session be collected.
  void detach(Object owner) {
    _owners.remove(owner);
    if (_owners.isEmpty) _latest = null;
  }
}

/// Publishes [AiToolFileActions] to descendants.
///
/// Hosts rebuild their transcript on every streamed chunk and hand in a freshly
/// constructed [AiToolFileActions] each time (it carries an `onOpenFile`
/// closure). `_AiToolFileActionsScope` compares by identity, so publishing every
/// new instance would mark each dependent — one per chain-of-thought block and
/// per tool card — dirty on every frame. This keeps the published instance
/// stable while the resolvers are unchanged and forwards the callback to the
/// newest host closure.
class AiToolFileActionsScope extends StatefulWidget {
  const AiToolFileActionsScope({
    required this.actions,
    required this.child,
    this.scopeId,
    super.key,
  });

  final AiToolFileActions actions;
  final Widget child;

  /// Identity of the owning surface (normally a session id). Constant across
  /// element rebuilds, so the published instance survives a remount without
  /// being shared with another surface that has the same resolvers.
  ///
  /// Null falls back to an identity owned by this element: two scopes can never
  /// share a published callback by accident (the failure mode that would open a
  /// file in the wrong seat). The cost is only that a remount republishes, so
  /// hot surfaces should pass a stable id.
  final Object? scopeId;

  @override
  State<AiToolFileActionsScope> createState() =>
      _AiToolFileActionsScopeState();
}

class _AiToolFileActionsScopeState extends State<AiToolFileActionsScope> {
  /// Per-element fallback owner when the host passes no [scopeId].
  final Object _localOwner = Object();
  _ActionsShape? _shape;

  @override
  void dispose() {
    final shape = _shape;
    final entry = shape == null ? null : _publishedActionsByShape[shape];
    entry?.detach(this);
    // Safe to drop the entry: a replacement element mounts (and re-attaches)
    // before the old one is disposed, so an empty owner set means nothing is
    // using it any more.
    if (shape != null && entry != null && !entry.hasOwners) {
      _publishedActionsByShape.remove(shape);
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    assert(() {
      aiToolFileActionsScopeStats.stateCreations++;
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.actions;
    final shape = _shapeOf(next, widget.scopeId ?? _localOwner);
    _shape = shape;
    var entry = _publishedActionsByShape[shape];
    if (entry == null) {
      assert(() {
        aiToolFileActionsScopeStats.republishes++;
        return true;
      }());
      entry = _PublishedActions(next);
      _publishedActionsByShape[shape] = entry;
    }
    entry.attach(this, next);
    return _AiToolFileActionsScope(actions: entry.value, child: widget.child);
  }
}

class _AiToolFileActionsScope extends InheritedWidget {
  const _AiToolFileActionsScope({
    required this.actions,
    required super.child,
  });

  final AiToolFileActions actions;

  @override
  bool updateShouldNotify(_AiToolFileActionsScope oldWidget) =>
      !identical(actions, oldWidget.actions);
}

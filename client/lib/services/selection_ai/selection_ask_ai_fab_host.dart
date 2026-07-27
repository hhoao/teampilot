import 'package:flutter/material.dart';

class SelectionAskAiFabHost extends StatefulWidget {
  const SelectionAskAiFabHost({
    required this.listenable,
    required this.selectionActive,
    required this.readAiContext,
    required this.onAskAi,
    required this.child,
    this.anchorGlobal,
    this.menuOpen = false,
    super.key,
  });

  final Listenable listenable;
  final bool Function() selectionActive;
  final String Function() readAiContext;
  final Future<void> Function(String aiContext) onAskAi;
  final Widget child;
  final Offset Function(BuildContext context)? anchorGlobal;
  final bool menuOpen;

  @override
  State<SelectionAskAiFabHost> createState() => _SelectionAskAiFabHostState();
}

class _SelectionAskAiFabHostState extends State<SelectionAskAiFabHost> {
  var _showFab = false;
  var _evaluationGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onSelectionChanged);
    _scheduleEvaluation();
  }

  @override
  void didUpdateWidget(SelectionAskAiFabHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onSelectionChanged);
      widget.listenable.addListener(_onSelectionChanged);
    }
    _onSelectionChanged();
  }

  @override
  void dispose() {
    _evaluationGeneration++;
    widget.listenable.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (_showFab &&
        (!widget.selectionActive() ||
            widget.readAiContext().trim().isEmpty ||
            widget.menuOpen)) {
      setState(() => _showFab = false);
    }
    _scheduleEvaluation();
  }

  void _scheduleEvaluation() {
    final generation = ++_evaluationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _evaluationGeneration) return;
      final shouldShow =
          !widget.menuOpen &&
          widget.selectionActive() &&
          widget.readAiContext().trim().isNotEmpty;
      if (_showFab != shouldShow) {
        setState(() => _showFab = shouldShow);
      }
    });
  }

  Future<void> _askAi() async {
    final aiContext = widget.readAiContext();
    if (aiContext.trim().isEmpty || !widget.selectionActive()) return;
    await widget.onAskAi(aiContext);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [widget.child, if (_showFab) _buildFab(context)],
    );
  }

  Widget _buildFab(BuildContext context) {
    final button = Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: const Icon(Icons.chat_outlined),
        onPressed: _askAi,
      ),
    );
    final anchorGlobal = widget.anchorGlobal;
    if (anchorGlobal == null) {
      return Positioned(right: 16, bottom: 16, child: button);
    }

    final renderObject = context.findRenderObject();
    final anchor = renderObject is RenderBox
        ? renderObject.globalToLocal(anchorGlobal(context))
        : Offset.zero;
    return Positioned(left: anchor.dx, top: anchor.dy, child: button);
  }
}

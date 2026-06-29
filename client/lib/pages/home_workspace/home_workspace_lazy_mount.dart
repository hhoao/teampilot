import 'package:flutter/material.dart';

/// Mounts [child] on the frame after [mountKey] changes so identity/tab
/// transitions can finish before heavy bodies (e.g. member form) build.
class HomeWorkspaceLazyMount extends StatefulWidget {
  const HomeWorkspaceLazyMount({
    required this.mountKey,
    required this.child,
    super.key,
  });

  final Object mountKey;
  final Widget child;

  @override
  State<HomeWorkspaceLazyMount> createState() => _HomeWorkspaceLazyMountState();
}

class _HomeWorkspaceLazyMountState extends State<HomeWorkspaceLazyMount> {
  var _mounted = false;
  Object? _activeKey;

  @override
  void initState() {
    super.initState();
    _scheduleMount();
  }

  @override
  void didUpdateWidget(covariant HomeWorkspaceLazyMount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mountKey != widget.mountKey) {
      _scheduleMount();
    }
  }

  void _scheduleMount() {
    setState(() {
      _mounted = false;
      _activeKey = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _mounted = true;
        _activeKey = widget.mountKey;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted || _activeKey != widget.mountKey) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}

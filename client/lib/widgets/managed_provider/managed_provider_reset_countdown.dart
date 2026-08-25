import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

/// Relative reset countdown helpers shared by quota meter and usage panel.
class ManagedProviderResetCountdown {
  const ManagedProviderResetCountdown._();

  static String? label(
    AppLocalizations l10n,
    int? resetsAt, {
    DateTime? now,
  }) {
    if (resetsAt == null) return null;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final remainingMs = resetsAt - nowMs;
    if (remainingMs <= 0) return l10n.managedProvidersResetsSoon;
    return l10n.managedProvidersResetsIn(
      formatDuration(Duration(milliseconds: remainingMs)),
    );
  }

  static String formatDuration(Duration remaining) {
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${remaining.inSeconds}s';
  }
}

/// Live-updating reset countdown label.
///
/// When [now] is set (tests), the label is static and no timer is started.
class ManagedProviderResetCountdownLabel extends StatefulWidget {
  const ManagedProviderResetCountdownLabel({
    required this.resetsAt,
    this.now,
    this.style,
    super.key,
  });

  final int? resetsAt;
  final DateTime? now;
  final TextStyle? style;

  @override
  State<ManagedProviderResetCountdownLabel> createState() =>
      _ManagedProviderResetCountdownLabelState();
}

class _ManagedProviderResetCountdownLabelState
    extends State<ManagedProviderResetCountdownLabel> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(covariant ManagedProviderResetCountdownLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetsAt != widget.resetsAt || oldWidget.now != widget.now) {
      _now = widget.now ?? DateTime.now();
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleTick() {
    _timer?.cancel();
    _timer = null;
    if (widget.now != null) return;

    final resetsAt = widget.resetsAt;
    if (resetsAt == null) return;

    final remainingMs = resetsAt - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return;

    final interval = remainingMs < const Duration(hours: 1).inMilliseconds
        ? const Duration(seconds: 1)
        : const Duration(minutes: 1);
    _timer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = ManagedProviderResetCountdown.label(
      context.l10n,
      widget.resetsAt,
      now: _now,
    );
    if (label == null) return const SizedBox.shrink();
    return Text(
      label,
      key: const Key('managed-provider-reset-countdown'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}

import 'dart:io';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../services/storage/home_target_controller.dart';

/// Platform-scoped home target selector. Replaces the legacy
/// connection-mode / Windows-backend / select-profile knobs.
///
/// - non-Windows desktop: only `local` (read-only "This device").
/// - Windows desktop: `local` + `wsl:<distro>`.
/// - Android: `ssh:*` profiles.
class RuntimeTargetPicker extends StatefulWidget {
  const RuntimeTargetPicker({
    super.key,
    this.isAndroidOverride,
    this.isWindowsOverride,
  });

  /// Test seams for platform-scoped rendering.
  final bool? isAndroidOverride;
  final bool? isWindowsOverride;

  @override
  State<RuntimeTargetPicker> createState() => _RuntimeTargetPickerState();
}

class _RuntimeTargetPickerState extends State<RuntimeTargetPicker> {
  late Future<List<RuntimeTarget>> _targets;
  bool _switching = false;

  bool get _isAndroid => widget.isAndroidOverride ?? Platform.isAndroid;
  bool get _isWindows => widget.isWindowsOverride ?? Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _targets = _load();
  }

  Future<List<RuntimeTarget>> _load() {
    final controller = context.read<HomeTargetController>();
    final currentId = controller.currentId;
    final wslDistro = runtimeKindOfId(currentId) == RuntimeKind.wsl
        ? (wslDistroOfId(currentId) ?? '')
        : '';
    return controller.listSelectable(wslDistro: wslDistro);
  }

  Iterable<RuntimeTarget> _scoped(List<RuntimeTarget> all) {
    if (_isAndroid) return all.where((t) => t.kind == RuntimeKind.ssh);
    if (_isWindows) {
      return all.where(
        (t) => t.kind == RuntimeKind.local || t.kind == RuntimeKind.wsl,
      );
    }
    return all.where((t) => t.kind == RuntimeKind.local);
  }

  Future<void> _select(String id) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      await context.read<HomeTargetController>().select(id);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Widget _trailing(BuildContext context, List<RuntimeTarget> options) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    final controller = context.read<HomeTargetController>();
    final currentId = controller.currentId;
    final value = options.any((t) => t.id == currentId)
        ? currentId
        : options.first.id;

    return TpCompactSelect<String>(
      value: value,
      enabled: !_switching,
      entries: [
        for (final t in options) (t.id, t.label),
      ],
      onChanged: (id) {
        if (id == null || id == currentId) return;
        _select(id);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<List<RuntimeTarget>>(
      future: _targets,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return TpPreferenceRow(
            title: l10n.homeTargetTitle,
            subtitle: l10n.homeTargetSubtitle,
            crossAxisAlignment: CrossAxisAlignment.start,
            trailing: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final options = _scoped(snapshot.data!).toList();
        return TpPreferenceRow(
          title: l10n.homeTargetTitle,
          subtitle: l10n.homeTargetSubtitle,
          crossAxisAlignment: CrossAxisAlignment.start,
          trailing: _trailing(context, options),
        );
      },
    );
  }
}

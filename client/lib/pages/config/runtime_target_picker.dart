import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/runtime_target.dart';
import '../../services/storage/home_target_controller.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<HomeTargetController>();
    return SettingsLabeledStackedRow(
      title: l10n.homeTargetTitle,
      subtitle: l10n.homeTargetSubtitle,
      showDividerBelow: true,
      body: FutureBuilder<List<RuntimeTarget>>(
        future: _targets,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            );
          }
          final options = _scoped(snapshot.data!).toList();
          final currentId = controller.currentId;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final t in options)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: t.id,
                  groupValue: currentId,
                  title: Text(t.label),
                  subtitle: Text(t.id),
                  onChanged: _switching || t.id == currentId
                      ? null
                      : (id) {
                          if (id != null) _select(id);
                        },
                ),
              if (options.length <= 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.homeTargetSingleOptionHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

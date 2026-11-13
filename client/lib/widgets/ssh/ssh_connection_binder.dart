import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/ssh_workload_profile_cubit.dart';
import '../../models/ssh_profile.dart';
import '../../services/ssh/ssh_host_profile_assembly.dart';
import '../../services/storage/home_target_controller.dart';

/// Keeps [SshConnectionCubit] host VMs in sync with the home-plane workload
/// catalog (B source) plus the current SSH home profile (from the device-local
/// A source). The home is kept in the cubit so boot reconnect and
/// `SshHomeDisconnectedBanner` can still `connect(pid)`; the status bar hides
/// it again through `SshConnectionState.excluding`.
class SshConnectionBinder extends StatefulWidget {
  const SshConnectionBinder({required this.child, super.key});

  final Widget child;

  @override
  State<SshConnectionBinder> createState() => _SshConnectionBinderState();
}

class _SshConnectionBinderState extends State<SshConnectionBinder> {
  var _syncing = false;
  List<SshProfile>? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestSync(_assembled(context));
    });
  }

  /// Single assembly point shared with `shell_boot.reconnectHomeSshIfNeeded`,
  /// so the binder and boot never disagree about the synced list.
  List<SshProfile> _assembled(BuildContext context) =>
      assembleSshHostProfiles(
        workloadProfiles:
            context.read<SshWorkloadProfileCubit>().state.profiles,
        deviceProfiles: context.read<SshProfileCubit>().state.profiles,
        home: context.read<HomeTargetController>().current,
      );

  void _requestSync(List<SshProfile> profiles) {
    _pending = profiles;
    if (_syncing) return;
    unawaited(_drainSync());
  }

  Future<void> _drainSync() async {
    _syncing = true;
    try {
      while (true) {
        final profiles = _pending;
        if (profiles == null) break;
        _pending = null;
        if (!mounted) return;
        final cubit = context.read<SshConnectionCubit>();
        if (cubit.isClosed) return;
        await cubit.syncProfiles(profiles);
        if (!mounted || cubit.isClosed) return;
      }
    } finally {
      _syncing = false;
      if (_pending != null && mounted) {
        unawaited(_drainSync());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SshWorkloadProfileCubit, SshProfileState>(
          listenWhen: (previous, next) =>
              !listEquals(previous.profiles, next.profiles),
          listener: (context, state) => _requestSync(_assembled(context)),
        ),
        BlocListener<SshProfileCubit, SshProfileState>(
          listenWhen: (previous, next) =>
              !listEquals(previous.profiles, next.profiles),
          listener: (context, state) => _requestSync(_assembled(context)),
        ),
      ],
      child: widget.child,
    );
  }
}

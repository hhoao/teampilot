import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../models/ssh_profile.dart';

/// Keeps [SshConnectionCubit] host VMs in sync with [SshProfileCubit] profiles.
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
      _requestSync(context.read<SshProfileCubit>().state.profiles);
    });
  }

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
    return BlocListener<SshProfileCubit, SshProfileState>(
      listenWhen: (previous, next) =>
          !listEquals(previous.profiles, next.profiles),
      listener: (context, state) => _requestSync(state.profiles),
      child: widget.child,
    );
  }
}

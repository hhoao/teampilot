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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncProfiles(context.read<SshProfileCubit>().state.profiles));
    });
  }

  Future<void> _syncProfiles(List<SshProfile> profiles) async {
    if (!mounted) return;
    await context.read<SshConnectionCubit>().syncProfiles(profiles);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SshProfileCubit, SshProfileState>(
      listenWhen: (previous, next) =>
          !listEquals(previous.profiles, next.profiles),
      listener: (context, state) {
        unawaited(_syncProfiles(state.profiles));
      },
      child: widget.child,
    );
  }
}

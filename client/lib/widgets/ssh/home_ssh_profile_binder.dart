import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../models/ssh_profile.dart';
import '../../services/storage/home_storage_invalidator.dart';

/// Routes SSH catalog diffs that affect home into [HomeStorageInvalidator].
///
/// Keeps [SshProfileCubit] free of AppStorage / workspace reload side effects.
class HomeSshProfileBinder extends StatefulWidget {
  const HomeSshProfileBinder({required this.child, super.key});

  final Widget child;

  @override
  State<HomeSshProfileBinder> createState() => _HomeSshProfileBinderState();
}

class _HomeSshProfileBinderState extends State<HomeSshProfileBinder> {
  List<SshProfile> _lastProfiles = const [];
  var _primed = false;
  var _applying = false;
  (List<SshProfile>, List<SshProfile>)? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastProfiles = List<SshProfile>.of(
        context.read<SshProfileCubit>().state.profiles,
      );
      _primed = true;
    });
  }

  void _requestApply(List<SshProfile> previous, List<SshProfile> next) {
    _pending = (previous, next);
    if (_applying) return;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    _applying = true;
    try {
      while (true) {
        final pending = _pending;
        if (pending == null) break;
        _pending = null;
        if (!mounted) return;
        final invalidator = context.read<HomeStorageInvalidator>();
        await invalidator.applyProfilesChanged(
          previous: pending.$1,
          next: pending.$2,
        );
        if (!mounted) return;
      }
    } finally {
      _applying = false;
      if (_pending != null && mounted) {
        unawaited(_drain());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SshProfileCubit, SshProfileState>(
      listenWhen: (previous, next) =>
          !listEquals(previous.profiles, next.profiles),
      listener: (context, state) {
        if (!_primed) {
          _lastProfiles = List<SshProfile>.of(state.profiles);
          _primed = true;
          return;
        }
        final previous = _lastProfiles;
        final next = List<SshProfile>.of(state.profiles);
        _lastProfiles = next;
        _requestApply(previous, next);
      },
      child: widget.child,
    );
  }
}

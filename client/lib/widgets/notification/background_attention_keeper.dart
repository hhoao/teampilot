import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../services/notification/background_attention_service.dart';

/// Keeps Android's foreground attention keeper in sync with the idle
/// notification preference. The native activity starts the service when it
/// pauses and stops it when it resumes, so background listeners get the
/// existing attention events without a permanent ongoing notification.
class BackgroundAttentionKeeper extends StatefulWidget {
  const BackgroundAttentionKeeper({
    required this.child,
    this.service,
    super.key,
  });

  final Widget child;
  final BackgroundAttentionService? service;

  @override
  State<BackgroundAttentionKeeper> createState() =>
      _BackgroundAttentionKeeperState();
}

class _BackgroundAttentionKeeperState extends State<BackgroundAttentionKeeper> {
  late final BackgroundAttentionService _service =
      widget.service ?? BackgroundAttentionService();
  SessionPreferencesCubit? _preferences;
  StreamSubscription<SessionPreferencesState>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<SessionPreferencesCubit>();
    if (identical(cubit, _preferences)) return;
    unawaited(_subscription?.cancel());
    _preferences = cubit;
    _subscription = cubit.stream.listen((_) => _sync());
    _sync();
  }

  void _sync() {
    final cubit = _preferences;
    if (cubit == null) return;
    unawaited(_service.setEnabled(cubit.state.preferences.notifyOnSessionIdle));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

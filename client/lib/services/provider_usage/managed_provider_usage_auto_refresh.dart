import 'dart:async';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';

/// Starts a 10-minute forced refresh loop for enabled Providers and cancels
/// in-flight work when a Provider is disabled.
class ManagedProviderUsageAutoRefresh {
  ManagedProviderUsageAutoRefresh({
    required ManagedProviderUsageCubit usage,
    required ManagedProviderCubit providers,
    Object Function(void Function() callback, Duration interval)? startPeriodic,
    void Function(Object handle)? stopPeriodic,
  }) : _usage = usage,
       _providers = providers,
       _startPeriodic = startPeriodic ?? _defaultStartPeriodic,
       _stopPeriodic = stopPeriodic ?? _defaultStopPeriodic;

  static const interval = Duration(minutes: 10);

  final ManagedProviderUsageCubit _usage;
  final ManagedProviderCubit _providers;
  final Object Function(void Function() callback, Duration interval)
  _startPeriodic;
  final void Function(Object handle) _stopPeriodic;

  StreamSubscription<ManagedProviderState>? _subscription;
  Object? _periodicHandle;
  var _started = false;
  Set<String> _enabledIds = {};

  static Object _defaultStartPeriodic(
    void Function() callback,
    Duration period,
  ) => Timer.periodic(period, (_) => callback());

  static void _defaultStopPeriodic(Object handle) {
    if (handle is Timer) handle.cancel();
  }

  void start() {
    if (_started) return;
    _started = true;
    _enabledIds = _enabledIdSet(_providers.state);
    _subscription = _providers.stream.listen(_onProviders);
    _periodicHandle = _startPeriodic(_onTick, interval);
    unawaited(_usage.refreshEnabled());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _subscription?.cancel();
    _subscription = null;
    final handle = _periodicHandle;
    _periodicHandle = null;
    if (handle != null) _stopPeriodic(handle);
  }

  void dispose() => stop();

  void _onTick() {
    if (!_started) return;
    unawaited(_usage.refreshEnabled());
  }

  void _onProviders(ManagedProviderState state) {
    final next = _enabledIdSet(state);
    final removed = _enabledIds.difference(next);
    _enabledIds = next;
    for (final id in removed) {
      unawaited(_usage.cancelForProvider(id));
    }
  }

  static Set<String> _enabledIdSet(ManagedProviderState state) => {
    for (final provider in state.enabledProviders) provider.id,
  };
}

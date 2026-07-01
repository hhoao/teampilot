import 'dart:async';

import '../services/team_bus/team_bus.dart';

typedef BusPollTick = Future<void> Function(TeamBus? bus);

/// Gates a periodic poll on a workspace-tab-scoped [TeamBus].
///
/// UI owners (typically one [RightToolsPanel] per title-bar tab) attach with
/// their [tabScopeId]. Polling runs while any owner remains; the most recently
/// attached scope wins when multiple owners overlap during workspace switches.
class ScopedBusPollGate {
  ScopedBusPollGate({
    required TeamBus? Function(String tabScopeId) busForScope,
    required BusPollTick onTick,
    Duration pollInterval = const Duration(milliseconds: 1500),
  })  : _busForScope = busForScope,
        _onTick = onTick,
        _pollInterval = pollInterval;

  final TeamBus? Function(String tabScopeId) _busForScope;
  final BusPollTick _onTick;
  final Duration _pollInterval;

  final Map<Object, String> _owners = {};
  Timer? _timer;
  bool _inFlight = false;

  bool get isAttached => _owners.isNotEmpty;

  void attachUi(String tabScopeId, [Object? owner]) {
    final token = owner ?? _defaultOwner;
    final wasAttached = isAttached;
    _owners[token] = tabScopeId;
    if (!wasAttached) {
      _startTimer();
      unawaited(_tick());
    } else {
      unawaited(_tick());
    }
  }

  void detachUi([Object? owner]) {
    final token = owner ?? _defaultOwner;
    if (!_owners.containsKey(token)) return;
    _owners.remove(token);
    if (isAttached) {
      unawaited(_tick());
      return;
    }
    _stopTimer();
    unawaited(_onTick(null));
  }

  void dispose() {
    _owners.clear();
    _stopTimer();
  }

  late final Object _defaultOwner = Object();

  String? get _activeScopeId {
    if (_owners.isEmpty) return null;
    return _owners.values.last;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!isAttached || _inFlight) return;
    _inFlight = true;
    try {
      final scopeId = _activeScopeId;
      final bus = scopeId == null ? null : _busForScope(scopeId);
      await _onTick(bus);
    } finally {
      _inFlight = false;
    }
  }
}

import '../../models/session_activity.dart';

/// Fires idle notifications on the rising edge of [SessionActivity.isReadyToChat].
final class SessionIdleNotifyGate {
  SessionIdleNotifyGate({required this.onIdleConfirmed});

  final void Function(Set<String> sessionIds) onIdleConfirmed;

  Map<String, SessionActivity> _previous = {};

  void handle(Map<String, SessionActivity> activities) {
    final confirmed = <String>{};
    final allIds = {..._previous.keys, ...activities.keys};
    for (final id in allIds) {
      final wasReady = _previous[id]?.isReadyToChat == true;
      final isReady = activities[id]?.isReadyToChat == true;
      if (!wasReady && isReady) {
        confirmed.add(id);
      }
    }
    _previous = Map<String, SessionActivity>.from(activities);
    if (confirmed.isNotEmpty) onIdleConfirmed(confirmed);
  }

  void dispose() {
    _previous = {};
  }
}

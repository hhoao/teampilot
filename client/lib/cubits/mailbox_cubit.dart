import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/team_bus/bus_feed_entry.dart';
import '../services/team_bus/team_bus.dart';

class MailboxState extends Equatable {
  const MailboxState({this.entries = const [], this.totalUnread = 0});

  final List<BusFeedEntry> entries;
  final int totalUnread;

  @override
  List<Object?> get props => [entries, totalUnread];
}

/// Polls the active tab's [TeamBus] for the full-team message feed while a
/// mailbox view is mounted. Mirrors MemberPresenceCubit's attach/detach poll.
class MailboxCubit extends Cubit<MailboxState> {
  MailboxCubit({
    required TeamBus? Function() activeBus,
    Duration pollInterval = const Duration(milliseconds: 1500),
  })  : _activeBus = activeBus,
        _pollInterval = pollInterval,
        super(const MailboxState());

  final TeamBus? Function() _activeBus;
  final Duration _pollInterval;
  Timer? _timer;
  bool _attached = false;
  bool _inFlight = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    _timer?.cancel();
    unawaited(_tick());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _timer?.cancel();
    _timer = null;
    if (state.entries.isNotEmpty || state.totalUnread != 0) {
      emit(const MailboxState());
    }
  }

  Future<void> _tick() async {
    if (!_attached || _inFlight) return;
    final bus = _activeBus();
    if (bus == null) {
      if (state.entries.isNotEmpty) emit(const MailboxState());
      return;
    }
    _inFlight = true;
    try {
      final entries = await bus.messagesSnapshot();
      if (!_attached || isClosed) return;
      final unread = entries.where((e) => e.isUnread).length;
      final next = MailboxState(entries: entries, totalUnread: unread);
      if (next != state) emit(next);
    } finally {
      _inFlight = false;
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}

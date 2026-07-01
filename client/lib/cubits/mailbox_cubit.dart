import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/team_bus/bus_feed_entry.dart';
import '../services/team_bus/team_bus.dart';
import 'scoped_bus_poll_gate.dart';

class MailboxState extends Equatable {
  const MailboxState({this.entries = const [], this.totalUnread = 0});

  final List<BusFeedEntry> entries;
  final int totalUnread;

  @override
  List<Object?> get props => [entries, totalUnread];
}

/// Polls a workspace-tab-scoped [TeamBus] for the full-team message feed while
/// a [RightToolsPanel] for that tab is foreground-attached.
class MailboxCubit extends Cubit<MailboxState> {
  MailboxCubit({
    required TeamBus? Function(String tabScopeId) busForScope,
    Duration pollInterval = const Duration(milliseconds: 1500),
  }) : super(const MailboxState()) {
    _poll = ScopedBusPollGate(
      busForScope: busForScope,
      pollInterval: pollInterval,
      onTick: _pollBus,
    );
  }

  late final ScopedBusPollGate _poll;

  void attachUi(String tabScopeId, [Object? owner]) =>
      _poll.attachUi(tabScopeId, owner);

  void detachUi([Object? owner]) => _poll.detachUi(owner);

  Future<void> _pollBus(TeamBus? bus) async {
    if (isClosed) return;
    if (bus == null) {
      if (state.entries.isNotEmpty || state.totalUnread != 0) {
        emit(const MailboxState());
      }
      return;
    }
    final entries = await bus.messagesSnapshot();
    if (isClosed || !_poll.isAttached) return;
    final unread = entries.where((e) => e.isUnread).length;
    final next = MailboxState(entries: entries, totalUnread: unread);
    if (next != state) emit(next);
  }

  @override
  Future<void> close() {
    _poll.dispose();
    return super.close();
  }
}

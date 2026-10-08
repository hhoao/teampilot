import 'package:equatable/equatable.dart';

import '../../models/app_session.dart';
import '../../models/workspace.dart';

class ChatDataSnapshot extends Equatable {
  const ChatDataSnapshot({
    required this.workspaces,
    required this.sessions,
    required this.visibleWorkspaces,
    required this.visibleSessions,
  });

  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final List<Workspace> visibleWorkspaces;
  final List<AppSession> visibleSessions;

  @override
  List<Object?> get props => [
    workspaces,
    sessions,
    visibleWorkspaces,
    visibleSessions,
  ];
}

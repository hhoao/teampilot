import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/cubits/chat_state.dart';
import 'package:teampilot/services/chat/session/session_data_store.dart';
import 'package:teampilot/cubits/chat_state_port.dart';
import 'package:teampilot/services/chat/launch/launch_environment_port.dart';
import 'package:teampilot/services/chat/session/session_repository_port.dart';
import 'package:teampilot/services/chat/session/tab_port.dart';
import 'package:teampilot/services/chat/launch/session_launch_host.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/chat/launch/session/session_persistence_writer.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';

import 'in_memory_filesystem.dart';

/// A [SessionPersistenceWriter] wired to inert collaborators.
///
/// For tests that build a `SessionShellConnector` but never exercise the
/// persistence path: there is no session repository, no global presets, and no
/// open tabs, so every operation is a no-op. Nothing is recorded.
SessionPersistenceWriter inertSessionPersistenceWriter() =>
    SessionPersistenceWriter(
      repository: _InertRepository(),
      snapshots: _InertSnapshots(),
      chatState: _InertChatState(),
      tabs: _InertTabs(),
      environment: _InertEnvironment(),
      dataStore: SessionDataStore(storage: fakeHomeStorage()),
    );

class _InertRepository implements SessionRepositoryPort {
  @override
  SessionRepository? get sessionRepository => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _InertSnapshots implements SessionSnapshotPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _InertChatState implements ChatStatePort {
  @override
  ChatState state = ChatState();

  @override
  bool get isClosed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _InertTabs implements TabPort {
  @override
  final ChatTabStore tabStore = ChatTabStore(storage: fakeHomeStorage());

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _InertEnvironment implements LaunchEnvironmentPort {
  @override
  final SessionLifecycleService lifecycle = SessionLifecycleService(
    storage: fakeHomeStorage(),
    loadPresets: () => const [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

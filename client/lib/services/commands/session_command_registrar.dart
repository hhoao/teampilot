import '../../cubits/chat_cubit.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Wires the v1 session-tab commands onto [bus] against [chat].
///
/// Call once during app bootstrap, after both are constructed (see
/// `buildAppShell`); handlers stay registered for the app's lifetime, so
/// there is no matching unregister step.
void registerSessionCommands(CommandBus bus, ChatCubit chat) {
  bus.register(CommandIds.sessionNextTab, () => chat.selectNextSessionTab());
  bus.register(
    CommandIds.sessionPrevTab,
    () => chat.selectPreviousSessionTab(),
  );
  bus.register(
    CommandIds.sessionNewTab,
    () => chat.enterNewChat(chat.tabStore.activeWorkspaceId),
  );
  bus.register(
    CommandIds.sessionCloseTab,
    () => chat.closeTab(chat.state.activeTabIndex),
  );
  for (var n = 1; n <= 10; n++) {
    final ordinal = n;
    bus.register(
      CommandIds.sessionFocusTab(ordinal),
      () => chat.selectSessionTabAt(ordinal),
    );
  }
}

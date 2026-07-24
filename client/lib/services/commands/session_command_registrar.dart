import '../../cubits/chat_cubit.dart';
import '../workbench/workbench_strip_navigator.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Wires workbench-strip + session create/close commands onto [bus].
///
/// Call once during app bootstrap after [WorkbenchStripNavigator] is built
/// (see `buildAppShell`); handlers stay registered for the app's lifetime.
void registerSessionCommands(
  CommandBus bus,
  ChatCubit chat,
  WorkbenchStripNavigator strip,
) {
  bus.register(CommandIds.stripNextTab, strip.next);
  bus.register(CommandIds.stripPrevTab, strip.previous);
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
      CommandIds.stripFocusTab(ordinal),
      () => strip.focusAt(ordinal),
    );
  }
}

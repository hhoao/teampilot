import '../../router/app_router.dart';
import '../../widgets/shortcuts/shortcut_cheatsheet_dialog.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Wires [CommandIds.showCheatsheet] onto [bus].
///
/// The command has no natural "owning" widget, so it reaches the UI through
/// the app's root [appRouter] navigator rather than a per-widget handler —
/// call once during app bootstrap, alongside `registerLayoutCommands` /
/// `registerSessionCommands`.
void registerShortcutsUiCommands(CommandBus bus) {
  bus.register(CommandIds.showCheatsheet, () {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    showShortcutCheatsheetDialog(context);
  });
}

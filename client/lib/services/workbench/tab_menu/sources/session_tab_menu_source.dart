import '../workbench_tab_menu_context.dart';
import '../workbench_tab_menu_source.dart';

/// Reserved for future session-only tab menu actions.
class SessionTabMenuSource implements WorkbenchTabMenuSource {
  const SessionTabMenuSource();

  @override
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx) =>
      const [];
}

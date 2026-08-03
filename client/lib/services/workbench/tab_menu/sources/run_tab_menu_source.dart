import '../workbench_tab_menu_context.dart';
import '../workbench_tab_menu_source.dart';

/// Reserved for future run-tab menu actions.
class RunTabMenuSource implements WorkbenchTabMenuSource {
  const RunTabMenuSource();

  @override
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx) =>
      const [];
}

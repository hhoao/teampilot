import 'workbench_tab_menu_source.dart';
import 'sources/builtin_close_tab_menu_source.dart';
import 'sources/file_path_tab_menu_source.dart';
import 'sources/run_tab_menu_source.dart';
import 'sources/session_tab_menu_source.dart';

/// Default ordered tab menu sources shared by center and floating strips.
List<WorkbenchTabMenuSource> defaultWorkbenchTabMenuSources() => const [
  FilePathTabMenuSource(),
  SessionTabMenuSource(),
  RunTabMenuSource(),
  BuiltinCloseTabMenuSource(),
];

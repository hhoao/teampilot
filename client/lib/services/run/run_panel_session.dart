import '../../models/run/run_session.dart';
import 'launch_type_normalize.dart';

/// Whether [session] is shown as a Run tool-window tab (not a shell PTY).
///
/// Built-in shell-script launches own a terminal entry instead.
bool sessionUsesRunPanel(RunSession session) {
  return !isBuiltInShellType(session.owned.configuration.type);
}

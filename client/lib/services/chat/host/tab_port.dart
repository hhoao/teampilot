import '../../../models/team_config.dart';
import '../launch/team_config_launch_validator.dart';
import '../chat_tab_store.dart';
import '../model/chat_tab.dart';

/// Session tab lifecycle: the tab store, the active tab, member selection, and
/// the tab-scoped surfaces driven off them.
abstract interface class TabPort {
  ChatTabStore get tabStore;

  ChatTab? get activeTab;

  set activeTeam(TeamProfile? team);

  void assignSelectedMember(ChatTab tab, String memberId);

  void selectMember(String memberId, {String? tabScopeId});

  void closeSessionTab(String sessionId);

  void emitTeamConfigValidation(TeamConfigValidation validation);

  void pushPresenceTarget();
}

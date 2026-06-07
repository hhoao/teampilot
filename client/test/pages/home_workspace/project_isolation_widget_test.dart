import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chat tabs do not leak across projects', () {
    final cubit = ChatCubit(executableResolver: () => '/bin/true');
    cubit.setActiveProject('personal-A');
    cubit.tabStore.append(_tab('a-sess'));
    cubit.refreshActiveProjectTabs();
    expect(cubit.state.tabs.map((t) => t.id), ['a-sess']);

    // Two personal projects (both empty teamId) must not see each other's tabs.
    cubit.setActiveProject('personal-B');
    expect(cubit.state.tabs, isEmpty);

    cubit.setActiveProject('personal-A');
    expect(cubit.state.tabs.map((t) => t.id), ['a-sess']);
    addTearDown(cubit.close);
  });

  test('terminal group survives a project switch and is restored', () {
    final reg = WorkspaceTerminalRegistry();
    final groupA = reg.groupFor('A');
    final entry = groupA.addEntry(cwd: '/tmp/a', select: true);

    // Switch to B (group A is untouched in the registry).
    reg.groupFor('B');

    // Switch back to A: same group, same entry, same session instance.
    final restored = reg.groupFor('A');
    expect(identical(restored, groupA), isTrue);
    expect(restored.entries.single.id, entry.id);
    expect(identical(restored.entries.single.session, entry.session), isTrue);

    // Closing A's project tab disposes it.
    reg.disposeProject('A');
    expect(reg.groupFor('A').entries, isEmpty);
    reg.disposeAll();
  });
}

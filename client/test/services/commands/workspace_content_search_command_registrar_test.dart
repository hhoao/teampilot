import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/workspace_content_search_command_registrar.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_views.dart';

void main() {
  group('WorkspaceContentSearchHost', () {
    test('host binds, unbinds and opens the registered opener', () {
      final host = WorkspaceContentSearchHost();
      var calls = 0;
      void opener() => calls++;

      host.open();
      expect(calls, 0);

      host.bind(opener);
      host.open();
      expect(calls, 1);

      host.unbind(opener);
      host.open();
      expect(calls, 1);

      host.bind(opener);
      host.clear();
      host.open();
      expect(calls, 1);
    });

    test('registerWorkspaceContentSearchCommands invokes the host on the bus', () {
      final bus = CommandBus();
      final host = WorkspaceContentSearchHost();
      registerWorkspaceContentSearchCommands(bus, host);
      var calls = 0;
      host.bind(() => calls++);

      bus.invoke(CommandIds.workspaceContentSearch);

      expect(calls, 1);
    });
  });

  group('searchToolIndex', () {
    int index({
      bool isPersonalContext = false,
      bool membersVisible = true,
      bool fileTreeVisible = true,
      bool gitVisible = true,
      bool showMailbox = true,
      bool showBoard = true,
    }) {
      return searchToolIndex(
        isPersonalContext: isPersonalContext,
        membersVisible: membersVisible,
        fileTreeVisible: fileTreeVisible,
        gitVisible: gitVisible,
        showMailbox: showMailbox,
        showBoard: showBoard,
      );
    }

    test('all guards off yields index 0 (search is first and only view)', () {
      expect(
        index(
          membersVisible: false,
          fileTreeVisible: false,
          gitVisible: false,
          showMailbox: false,
          showBoard: false,
        ),
        0,
      );
    });

    test('order is members, fileTree, git, mailbox, board then search', () {
      expect(index(), 5);
      expect(
        index(
          showMailbox: false,
          showBoard: false,
        ),
        3,
      );
      expect(
        index(
          gitVisible: false,
          showMailbox: false,
          showBoard: false,
        ),
        2,
      );
      expect(
        index(
          fileTreeVisible: false,
          gitVisible: false,
          showMailbox: false,
          showBoard: false,
        ),
        1,
      );
    });

    test('personal context excludes the members view', () {
      expect(index(isPersonalContext: true), 4);
      expect(
        index(
          isPersonalContext: true,
          fileTreeVisible: false,
          gitVisible: false,
          showMailbox: false,
          showBoard: false,
        ),
        0,
      );
    });

    test('mailbox and board independently advance the index', () {
      expect(
        index(
          fileTreeVisible: false,
          gitVisible: false,
          showMailbox: true,
          showBoard: false,
        ),
        2,
      );
      expect(
        index(
          fileTreeVisible: false,
          gitVisible: false,
          showMailbox: true,
          showBoard: true,
        ),
        3,
      );
    });
  });
}

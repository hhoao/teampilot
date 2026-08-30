import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_tab_ref.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_shell.dart';
import 'package:teampilot/pages/home_workspace/workspace_chrome_commands.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';

const _a = WorkspaceTabRef(workspaceId: 'ws-a');
const _b = WorkspaceTabRef(workspaceId: 'ws-b');
const _c = WorkspaceTabRef(workspaceId: 'ws-c');

void main() {
  group('HomeShell.nextTab', () {
    test('is null with no open tabs', () {
      expect(
        HomeShell.nextTab(tabs: const [], activeTabKey: null),
        isNull,
      );
    });

    test('is a no-op (same tab) with a single open tab', () {
      final target = HomeShell.nextTab(
        tabs: const [_a],
        activeTabKey: _a.tabKey,
      );
      expect(target, _a);
    });

    test('wraps forward across open tabs', () {
      const tabs = [_a, _b, _c];

      expect(
        HomeShell.nextTab(tabs: tabs, activeTabKey: _a.tabKey),
        _b,
      );
      expect(
        HomeShell.nextTab(tabs: tabs, activeTabKey: _b.tabKey),
        _c,
      );
      expect(
        HomeShell.nextTab(tabs: tabs, activeTabKey: _c.tabKey),
        _a,
      );
    });

    test('starts from the first tab when no tab is active', () {
      expect(
        HomeShell.nextTab(tabs: const [_a, _b, _c], activeTabKey: null),
        _a,
      );
    });

    test('starts from the first tab when the active key is unknown', () {
      expect(
        HomeShell.nextTab(
          tabs: const [_a, _b, _c],
          activeTabKey: 'ws-unknown',
        ),
        _a,
      );
    });
  });

  group('HomeShell.prevTab', () {
    test('is null with no open tabs', () {
      expect(
        HomeShell.prevTab(tabs: const [], activeTabKey: null),
        isNull,
      );
    });

    test('is a no-op (same tab) with a single open tab', () {
      final target = HomeShell.prevTab(
        tabs: const [_a],
        activeTabKey: _a.tabKey,
      );
      expect(target, _a);
    });

    test('wraps backward across open tabs', () {
      const tabs = [_a, _b, _c];

      expect(
        HomeShell.prevTab(tabs: tabs, activeTabKey: _c.tabKey),
        _b,
      );
      expect(
        HomeShell.prevTab(tabs: tabs, activeTabKey: _b.tabKey),
        _a,
      );
      expect(
        HomeShell.prevTab(tabs: tabs, activeTabKey: _a.tabKey),
        _c,
      );
    });

    test('starts from the last tab when no tab is active', () {
      expect(
        HomeShell.prevTab(tabs: const [_a, _b, _c], activeTabKey: null),
        _c,
      );
    });
  });

  group('HomeShell.focusTabAt', () {
    test('is null with no open tabs', () {
      expect(
        HomeShell.focusTabAt(tabs: const [], oneBasedOrdinal: 1),
        isNull,
      );
    });

    test('picks the Nth open tab (1-based)', () {
      const tabs = [_a, _b, _c];

      expect(HomeShell.focusTabAt(tabs: tabs, oneBasedOrdinal: 1), _a);
      expect(HomeShell.focusTabAt(tabs: tabs, oneBasedOrdinal: 2), _b);
      expect(HomeShell.focusTabAt(tabs: tabs, oneBasedOrdinal: 3), _c);
    });

    test('is null out of range', () {
      const tabs = [_a, _b, _c];

      expect(HomeShell.focusTabAt(tabs: tabs, oneBasedOrdinal: 0), isNull);
      expect(HomeShell.focusTabAt(tabs: tabs, oneBasedOrdinal: 4), isNull);
    });
  });

  group('WorkspaceChromeCommands wired through CommandBus (fake host)', () {
    // Mimics the contract HomeShell.initState/dispose establishes: assign
    // real callbacks + openTabCount into a shared WorkspaceChromeCommands,
    // and register CommandBus handlers that delegate to the same private
    // logic — without mounting the real (heavyweight) HomeShell widget.
    late CommandBus bus;
    late WorkspaceChromeCommands host;
    late List<WorkspaceTabRef> openTabs;
    late List<WorkspaceTabRef> closedTabs;
    WorkspaceTabRef? selected;

    void mountFakeHomeShell() {
      void closeActive() {
        if (openTabs.isEmpty) return;
        final tab = openTabs.removeLast();
        closedTabs.insert(0, tab);
        host.openTabCount = openTabs.length;
      }

      void reopenClosed() {
        if (closedTabs.isEmpty) return;
        final tab = closedTabs.removeAt(0);
        openTabs.add(tab);
        selected = tab;
        host.openTabCount = openTabs.length;
      }

      void next() {
        final target = HomeShell.nextTab(
          tabs: openTabs,
          activeTabKey: selected?.tabKey,
        );
        if (target != null) selected = target;
      }

      void prev() {
        final target = HomeShell.prevTab(
          tabs: openTabs,
          activeTabKey: selected?.tabKey,
        );
        if (target != null) selected = target;
      }

      final focusTabHandlers = {
        for (var n = 1; n <= 10; n++)
          CommandIds.workspaceFocusTab(n): () {
            final target = HomeShell.focusTabAt(
              tabs: openTabs,
              oneBasedOrdinal: n,
            );
            if (target != null) selected = target;
          },
      };

      bus
        ..register(CommandIds.workspaceNextTab, next)
        ..register(CommandIds.workspacePrevTab, prev)
        ..register(CommandIds.workspaceCloseTab, closeActive)
        ..register(CommandIds.workspaceReopenClosed, reopenClosed);
      focusTabHandlers.forEach(bus.register);
      host
        ..nextWorkspaceTab = next
        ..prevWorkspaceTab = prev
        ..closeActiveWorkspaceTab = closeActive
        ..reopenClosedWorkspaceTab = reopenClosed
        ..openTabCount = openTabs.length;
    }

    setUp(() {
      bus = CommandBus();
      host = WorkspaceChromeCommands();
      openTabs = [_a, _b, _c];
      closedTabs = [];
      selected = _a;
      mountFakeHomeShell();
    });

    test('openTabCount reflects the open tab list once mounted', () {
      expect(host.openTabCount, 3);
    });

    test('workspaceNextTab / workspacePrevTab commands wrap via HomeShell logic', () {
      bus.invoke(CommandIds.workspaceNextTab);
      expect(selected, _b);

      bus.invoke(CommandIds.workspaceNextTab);
      bus.invoke(CommandIds.workspaceNextTab);
      expect(selected, _a);

      bus.invoke(CommandIds.workspacePrevTab);
      expect(selected, _c);
    });

    test('workspace.focusTabN commands select the Nth open tab', () {
      bus.invoke(CommandIds.workspaceFocusTab(3));
      expect(selected, _c);

      bus.invoke(CommandIds.workspaceFocusTab(1));
      expect(selected, _a);
    });

    test('workspace.focusTabN command is a no-op out of range', () {
      bus.invoke(CommandIds.workspaceFocusTab(4));
      expect(selected, _a);
    });

    test('workspaceCloseTab command closes the active tab and updates openTabCount', () {
      bus.invoke(CommandIds.workspaceCloseTab);

      expect(openTabs, [_a, _b]);
      expect(closedTabs, [_c]);
      expect(host.openTabCount, 2);
    });

    test(
      'workspaceReopenClosed command reopens the most recently closed tab',
      () {
        bus.invoke(CommandIds.workspaceCloseTab); // closes _c
        bus.invoke(CommandIds.workspaceCloseTab); // closes _b
        expect(closedTabs, [_b, _c]);

        bus.invoke(CommandIds.workspaceReopenClosed);

        expect(selected, _b);
        expect(openTabs, [_a, _b]);
        expect(closedTabs, [_c]);
        expect(host.openTabCount, 2);
      },
    );

    test('workspaceReopenClosed command is a no-op with nothing closed', () {
      bus.invoke(CommandIds.workspaceReopenClosed);

      expect(openTabs, [_a, _b, _c]);
      expect(host.openTabCount, 3);
    });

    test('dispose clears the host so callers see the unmounted state', () {
      host.clear();

      expect(host.nextWorkspaceTab, isNull);
      expect(host.prevWorkspaceTab, isNull);
      expect(host.closeActiveWorkspaceTab, isNull);
      expect(host.reopenClosedWorkspaceTab, isNull);
      expect(host.openTabCount, 0);
    });
  });

  group('HomeShell.resolveTabRoute', () {
    test('falls back to bare workspace path', () {
      expect(
        HomeShell.resolveTabRoute(tab: _a, restorableLocations: const {}),
        _a.route,
      );
    });

    test('restores last deep link including manage view', () {
      const manage =
          '/home-v2/workspace/ws-a?view=manage&section=settings';
      expect(
        HomeShell.resolveTabRoute(
          tab: _a,
          restorableLocations: {_a.tabKey: manage},
        ),
        manage,
      );
    });
  });
}

# Workspace Shell Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the corrected FlashskyAI desktop workbench shell with app rail, context sidebar, workspace topbar, local chat timeline, and right-side Members/File Tree tools.

**Architecture:** Keep `TeamController` responsible for saved team/member configuration and launching. Add a separate `ChatController` for local shell-mode conversation state and clipboard copying. Refactor UI out of `main.dart` into focused widgets that render the app rail, context sidebar, workspace topbar, chat workbench, right tools, and config workspace overview.

**Tech Stack:** Flutter, Material 3, `ChangeNotifier`, `shared_preferences`, `flutter_test`.

---

## Scope

This is the first implementation slice from `docs/superpowers/specs/2026-05-09-flashskyai-workbench-ui-design.md`.

In scope:

- Corrected workspace chrome.
- Chat view with app rail, context sidebar, workspace topbar, center chat, and right tools.
- Local chat messages copied to clipboard, with truthful shell-wrapper status text.
- Member selection as chat target.
- Existing team/member launch behavior preserved.
- Config rail view initial overview that uses full workspace width and does not show chat right tools.

Out of scope for this plan:

- Full Team Config editor redesign.
- Full Member Config editor redesign.
- LLM Config editor for `flashshkyai/llm/llm_config.json`.
- Drag-resizable panel persistence.
- Real native FlashskyAI chat transport.

## File Structure

- Create `client/lib/app_keys.dart`
  - Owns all stable widget keys used by tests and UI.
  - Preserve existing key names from `main.dart`.

- Create `client/lib/chat_models.dart`
  - Defines `ChatMessageRole` and `ChatMessage`.

- Create `client/lib/chat_controller.dart`
  - Owns local messages.
  - Owns selected target member id.
  - Copies prompts through injectable `ClipboardWriter`.
  - Adds local system messages for copied prompts and launch feedback.

- Create `client/lib/widgets/app_rail.dart`
  - Global navigation rail for Chat, Runs, Config.

- Create `client/lib/widgets/context_sidebar.dart`
  - Chat context sidebar with team selector, team sessions, and existing team list behavior.

- Create `client/lib/widgets/workspace_shell.dart`
  - Shared shell that places workspace topbar above main content and optional right tools.
  - Topbar spans center content and right tools, not app rail or context sidebar.

- Create `client/lib/widgets/chat_workbench.dart`
  - Center chat timeline and composer.

- Create `client/lib/widgets/right_tools_panel.dart`
  - Members stacked above File Tree.
  - File Tree can be a read-only top-level summary in this slice.

- Create `client/lib/widgets/config_workspace.dart`
  - Config initial overview page with no chat-style right tools.

- Modify `client/lib/main.dart`
  - Wire controllers and replace current two-column editor with the workbench shell.
  - Keep existing theme style.

- Modify `client/test/widget_test.dart`
  - Update tests for corrected workbench shell.

- Create `client/test/chat_controller_test.dart`
  - Unit tests for local shell-mode chat behavior.

## Task 1: Chat Models and Controller

**Files:**

- Create: `client/lib/chat_models.dart`
- Create: `client/lib/chat_controller.dart`
- Test: `client/test/chat_controller_test.dart`

- [ ] **Step 1: Write failing chat controller tests**

Create `client/test/chat_controller_test.dart`:

```dart
import 'package:flashskyai_client/chat_controller.dart';
import 'package:flashskyai_client/chat_models.dart';
import 'package:flashskyai_client/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingClipboardWriter implements ClipboardWriter {
  final copied = <String>[];

  @override
  Future<void> setText(String text) async {
    copied.add(text);
  }
}

void main() {
  const team = TeamConfig(
    id: 'team-1',
    name: 'Default Team',
    workingDirectory: '/work/current',
    members: [
      TeamMemberConfig(id: 'lead', name: 'team-lead'),
      TeamMemberConfig(id: 'coder', name: 'coder'),
    ],
  );

  test('selects team-lead as the default target', () {
    final controller = ChatController(clipboard: RecordingClipboardWriter());

    controller.syncTeam(team);

    expect(controller.selectedMemberId, 'lead');
    expect(controller.selectedMemberName(team), 'team-lead');
  });

  test('submitting a prompt records user message and copy status', () async {
    final clipboard = RecordingClipboardWriter();
    final controller = ChatController(clipboard: clipboard);
    controller.syncTeam(team);

    await controller.submitPrompt(team, '  continue the plan  ');

    expect(clipboard.copied, ['continue the plan']);
    expect(controller.messages, hasLength(2));
    expect(controller.messages[0].role, ChatMessageRole.user);
    expect(controller.messages[0].content, 'continue the plan');
    expect(controller.messages[1].role, ChatMessageRole.system);
    expect(
      controller.messages[1].content,
      'Copied prompt for team-lead. Paste it into the FlashskyAI terminal.',
    );
  });

  test('blank prompts are ignored', () async {
    final clipboard = RecordingClipboardWriter();
    final controller = ChatController(clipboard: clipboard);
    controller.syncTeam(team);

    await controller.submitPrompt(team, '   ');

    expect(clipboard.copied, isEmpty);
    expect(controller.messages, isEmpty);
  });

  test('selected target member can change', () {
    final controller = ChatController(clipboard: RecordingClipboardWriter());
    controller.syncTeam(team);

    controller.selectMember('coder');

    expect(controller.selectedMemberId, 'coder');
    expect(controller.selectedMemberName(team), 'coder');
  });

  test('adds a system launch status message', () {
    final controller = ChatController(clipboard: RecordingClipboardWriter());
    controller.syncTeam(team);

    controller.addSystemMessage(team.id, 'Started team-lead.');

    expect(controller.messages.single.role, ChatMessageRole.system);
    expect(controller.messages.single.content, 'Started team-lead.');
  });
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd client && flutter test test/chat_controller_test.dart
```

Expected: FAIL because `chat_controller.dart` and `chat_models.dart` do not exist.

- [ ] **Step 3: Implement chat models**

Create `client/lib/chat_models.dart`:

```dart
enum ChatMessageRole {
  user,
  system,
  assistantNote,
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.teamId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.memberId = '',
  });

  final String id;
  final String teamId;
  final ChatMessageRole role;
  final String content;
  final DateTime createdAt;
  final String memberId;
}
```

- [ ] **Step 4: Implement chat controller**

Create `client/lib/chat_controller.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chat_models.dart';
import 'team_config.dart';

abstract class ClipboardWriter {
  Future<void> setText(String text);
}

class SystemClipboardWriter implements ClipboardWriter {
  const SystemClipboardWriter();

  @override
  Future<void> setText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}

typedef ChatIdProvider = String Function();
typedef ChatClock = DateTime Function();

class ChatController extends ChangeNotifier {
  ChatController({
    required ClipboardWriter clipboard,
    ChatIdProvider? idProvider,
    ChatClock? clock,
  }) : _clipboard = clipboard,
       _idProvider =
           idProvider ?? (() => DateTime.now().microsecondsSinceEpoch.toString()),
       _clock = clock ?? DateTime.now;

  final ClipboardWriter _clipboard;
  final ChatIdProvider _idProvider;
  final ChatClock _clock;

  final _messages = <ChatMessage>[];
  String _selectedMemberId = '';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  String get selectedMemberId => _selectedMemberId;

  void syncTeam(TeamConfig team) {
    if (team.members.isEmpty) {
      _selectedMemberId = '';
      notifyListeners();
      return;
    }
    if (team.members.any((member) => member.id == _selectedMemberId)) {
      return;
    }
    final lead = team.members.where((member) => member.name == 'team-lead');
    _selectedMemberId = lead.isEmpty ? team.members.first.id : lead.first.id;
    notifyListeners();
  }

  void selectMember(String memberId) {
    if (_selectedMemberId == memberId) {
      return;
    }
    _selectedMemberId = memberId;
    notifyListeners();
  }

  String selectedMemberName(TeamConfig team) {
    for (final member in team.members) {
      if (member.id == _selectedMemberId) {
        return member.name;
      }
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  Future<void> submitPrompt(TeamConfig team, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final memberName = selectedMemberName(team);
    _messages.add(
      ChatMessage(
        id: _idProvider(),
        teamId: team.id,
        memberId: _selectedMemberId,
        role: ChatMessageRole.user,
        content: trimmed,
        createdAt: _clock(),
      ),
    );
    await _clipboard.setText(trimmed);
    _messages.add(
      ChatMessage(
        id: _idProvider(),
        teamId: team.id,
        memberId: _selectedMemberId,
        role: ChatMessageRole.system,
        content:
            'Copied prompt for $memberName. Paste it into the FlashskyAI terminal.',
        createdAt: _clock(),
      ),
    );
    notifyListeners();
  }

  void addSystemMessage(String teamId, String content) {
    _messages.add(
      ChatMessage(
        id: _idProvider(),
        teamId: teamId,
        role: ChatMessageRole.system,
        content: content,
        createdAt: _clock(),
      ),
    );
    notifyListeners();
  }
}
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run:

```bash
cd client && flutter test test/chat_controller_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add client/lib/chat_models.dart client/lib/chat_controller.dart client/test/chat_controller_test.dart
git commit -m "feat: add local chat controller"
```

## Task 2: App Keys and Widget Test Expectations

**Files:**

- Create: `client/lib/app_keys.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/test/widget_test.dart`

- [ ] **Step 1: Move stable keys into `app_keys.dart`**

Create `client/lib/app_keys.dart`:

```dart
import 'package:flutter/widgets.dart';

class AppKeys {
  const AppKeys._();

  static const appRailChatButton = Key('app-rail-chat-button');
  static const appRailRunsButton = Key('app-rail-runs-button');
  static const appRailConfigButton = Key('app-rail-config-button');
  static const contextSidebar = Key('context-sidebar');
  static const workspaceTopbar = Key('workspace-topbar');
  static const chatWorkspace = Key('chat-workspace');
  static const configWorkspace = Key('config-workspace');
  static const rightToolsPanel = Key('right-tools-panel');
  static const membersPanel = Key('members-panel');
  static const fileTreePanel = Key('file-tree-panel');
  static const chatInput = Key('chat-input');
  static const sendPromptButton = Key('send-prompt-button');
  static const copyPromptButton = Key('copy-prompt-button');
  static const openTeamLeadButton = Key('open-team-lead-button');
  static const openTeamButton = Key('open-team-button');

  static const teamNameField = Key('team-name-field');
  static const workingDirectoryField = Key('working-directory-field');
  static const extraArgsField = Key('extra-args-field');
  static const saveButton = Key('save-team-button');
  static const launchButton = Key('launch-team-button');
  static const addButton = Key('add-team-button');
  static const deleteButton = Key('delete-team-button');
  static const addMemberButton = Key('add-member-button');

  static Key memberRow(String id) => Key('member-row-$id');
  static Key memberNameField(String id) => Key('member-name-field-$id');
  static Key memberProviderField(String id) => Key('member-provider-field-$id');
  static Key memberModelField(String id) => Key('member-model-field-$id');
  static Key memberAgentField(String id) => Key('member-agent-field-$id');
  static Key memberExtraArgsField(String id) =>
      Key('member-extra-args-field-$id');
  static Key memberOpenButton(String id) => Key('member-open-button-$id');
  static Key memberDeleteButton(String id) => Key('member-delete-button-$id');
}
```

Remove the `AppKeys` class from `client/lib/main.dart` and add:

```dart
import 'app_keys.dart';
```

- [ ] **Step 2: Write failing widget tests for the corrected shell**

Replace the first test in `client/test/widget_test.dart` with:

```dart
testWidgets('renders corrected chat workbench shell', (tester) async {
  final controller = await createController();

  await tester.pumpWidget(FlashskyAiClientApp(controller: controller));
  await tester.pumpAndSettle();

  expect(find.byKey(AppKeys.appRailChatButton), findsOneWidget);
  expect(find.byKey(AppKeys.contextSidebar), findsOneWidget);
  expect(find.byKey(AppKeys.workspaceTopbar), findsOneWidget);
  expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);
  expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
  expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
  expect(find.byKey(AppKeys.fileTreePanel), findsOneWidget);
  expect(find.text('Default Team'), findsWidgets);
  expect(find.text('Team Sessions'), findsOneWidget);
  expect(find.text('Shell chat workbench'), findsWidgets);
  expect(find.text('team-lead'), findsWidgets);
});
```

Add this test:

```dart
testWidgets('config workspace uses full width without chat right tools', (
  tester,
) async {
  final controller = await createController();

  await tester.pumpWidget(FlashskyAiClientApp(controller: controller));
  await tester.tap(find.byKey(AppKeys.appRailConfigButton));
  await tester.pumpAndSettle();

  expect(find.byKey(AppKeys.configWorkspace), findsOneWidget);
  expect(find.text('Configuration'), findsWidgets);
  expect(find.byKey(AppKeys.rightToolsPanel), findsNothing);
});
```

- [ ] **Step 3: Run widget tests and verify they fail**

Run:

```bash
cd client && flutter test test/widget_test.dart
```

Expected: FAIL because the corrected shell widgets do not exist yet.

- [ ] **Step 4: Keep existing launcher tests compiling**

Update `client/test/widget_test.dart` import from:

```dart
import 'package:flashskyai_client/main.dart';
```

to:

```dart
import 'package:flashskyai_client/app_keys.dart';
import 'package:flashskyai_client/main.dart';
```

Expected: The test file should compile after Task 3 creates the new widgets.

- [ ] **Step 5: Commit after Task 3 passes**

Do not commit in this task until the UI implementation in Task 3 makes the tests pass.

## Task 3: Corrected Workspace Shell Widgets

**Files:**

- Create: `client/lib/widgets/app_rail.dart`
- Create: `client/lib/widgets/context_sidebar.dart`
- Create: `client/lib/widgets/workspace_shell.dart`
- Create: `client/lib/widgets/config_workspace.dart`
- Modify: `client/lib/main.dart`
- Test: `client/test/widget_test.dart`

- [ ] **Step 1: Create app rail widget**

Create `client/lib/widgets/app_rail.dart`:

```dart
import 'package:flutter/material.dart';

import '../app_keys.dart';

enum AppSection {
  chat,
  runs,
  config,
}

class AppRail extends StatelessWidget {
  const AppRail({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final AppSection selected;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      color: const Color(0xFF090D12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          const _Logo(),
          const SizedBox(height: 14),
          _RailButton(
            key: AppKeys.appRailChatButton,
            selected: selected == AppSection.chat,
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            onPressed: () => onSelected(AppSection.chat),
          ),
          const SizedBox(height: 10),
          _RailButton(
            key: AppKeys.appRailRunsButton,
            selected: selected == AppSection.runs,
            icon: Icons.play_circle_outline,
            label: 'Runs',
            onPressed: () => onSelected(AppSection.runs),
          ),
          const SizedBox(height: 10),
          _RailButton(
            key: AppKeys.appRailConfigButton,
            selected: selected == AppSection.config,
            icon: Icons.tune_outlined,
            label: 'Config',
            onPressed: () => onSelected(AppSection.config),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          colors: [Color(0xFF60A5FA), Color(0xFF34D399)],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor:
              selected ? const Color(0x3D60A5FA) : const Color(0x1F94A3B8),
          foregroundColor:
              selected ? const Color(0xFFDBEAFE) : Colors.white70,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
```

- [ ] **Step 2: Create context sidebar**

Create `client/lib/widgets/context_sidebar.dart`:

```dart
import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../team_config.dart';
import '../team_controller.dart';

class ContextSidebar extends StatelessWidget {
  const ContextSidebar({
    required this.controller,
    required this.selectedSectionLabel,
    super.key,
  });

  final TeamController controller;
  final String selectedSectionLabel;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedTeam;
    return Container(
      key: AppKeys.contextSidebar,
      width: 260,
      color: const Color(0xFF111827),
      padding: const EdgeInsets.all(13),
      child: selected == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TeamSelector(controller: controller, selected: selected),
                const SizedBox(height: 14),
                _SidebarSectionTitle(
                  title: selectedSectionLabel == 'Config'
                      ? 'Configure'
                      : 'Team Sessions',
                  actionLabel: selectedSectionLabel == 'Config' ? '' : '+',
                ),
                if (selectedSectionLabel == 'Config') ...[
                  const _SidebarTile(
                    title: 'Team Settings',
                    subtitle: 'workspace teams',
                    selected: true,
                  ),
                  const _SidebarTile(
                    title: 'Members',
                    subtitle: 'team agents',
                    selected: false,
                  ),
                  const _SidebarTile(
                    title: 'LLM Config',
                    subtitle: 'providers and models',
                    selected: false,
                  ),
                  const _SidebarTile(
                    title: 'Layout',
                    subtitle: 'global workbench',
                    selected: false,
                  ),
                ] else ...[
                  const _SidebarTile(
                    title: 'Shell chat workbench',
                    subtitle: 'team-lead / local',
                    selected: true,
                  ),
                  const _SidebarTile(
                    title: 'Fix Linux launch',
                    subtitle: 'reviewer / stopped',
                    selected: false,
                  ),
                  const _SidebarTile(
                    title: 'Docs cleanup',
                    subtitle: 'team-lead / unknown',
                    selected: false,
                  ),
                ],
              ],
            ),
    );
  }
}

class _TeamSelector extends StatelessWidget {
  const _TeamSelector({required this.controller, required this.selected});

  final TeamController controller;
  final TeamConfig selected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Select team',
      onSelected: controller.selectTeam,
      itemBuilder: (context) => [
        for (final team in controller.teams)
          PopupMenuItem(value: team.id, child: Text(team.name)),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: const Color(0x2B1E40AF),
          border: Border.all(color: const Color(0x5260A5FA)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  const _SidebarSectionTitle({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (actionLabel.isNotEmpty)
            Text(actionLabel, style: const TextStyle(color: Color(0xFF93C5FD))),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.title,
    required this.subtitle,
    required this.selected,
  });

  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color:
            selected ? const Color(0x2E1E40AF) : const Color(0x9E0F172A),
        border: Border.all(
          color:
              selected ? const Color(0x7360A5FA) : const Color(0x2B94A3B8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Create workspace shell**

Create `client/lib/widgets/workspace_shell.dart`:

```dart
import 'package:flutter/material.dart';

import '../app_keys.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.breadcrumb,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.child,
    this.rightTools,
    super.key,
  });

  final String breadcrumb;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget child;
  final Widget? rightTools;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            key: AppKeys.workspaceTopbar,
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1017),
              border: Border(
                bottom: BorderSide(color: Color(0x2E94A3B8)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.52),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(spacing: 8, children: actions),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: child),
                if (rightTools != null) rightTools!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Create config overview**

Create `client/lib/widgets/config_workspace.dart`:

```dart
import 'package:flutter/material.dart';

import '../app_keys.dart';

class ConfigWorkspace extends StatelessWidget {
  const ConfigWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: AppKeys.configWorkspace,
      color: const Color(0xFF090D13),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Configuration',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Team, Member, Layout, and LLM configuration will live here as full workspace views.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.64)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x2B94A3B8)),
              ),
              padding: const EdgeInsets.all(16),
              child: const Text(
                'No chat right-side tools on configuration pages.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Refactor `main.dart` into shell state**

In `client/lib/main.dart`:

1. Import:

```dart
import 'app_keys.dart';
import 'chat_controller.dart';
import 'widgets/app_rail.dart';
import 'widgets/chat_workbench.dart';
import 'widgets/config_workspace.dart';
import 'widgets/context_sidebar.dart';
import 'widgets/right_tools_panel.dart';
import 'widgets/workspace_shell.dart';
```

2. Remove the local `AppKeys` class.

3. In `FlashskyAiClientApp`, create a default chat controller when one is not supplied:

```dart
class FlashskyAiClientApp extends StatelessWidget {
  FlashskyAiClientApp({
    required this.controller,
    ChatController? chatController,
    super.key,
  }) : chatController =
           chatController ??
           ChatController(clipboard: const SystemClipboardWriter());

  final TeamController controller;
  final ChatController chatController;
```

4. Change home to:

```dart
home: WorkbenchPage(
  controller: controller,
  chatController: chatController,
),
```

5. Replace `TeamLauncherPage` with `WorkbenchPage`:

```dart
class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({
    required this.controller,
    required this.chatController,
    super.key,
  });

  final TeamController controller;
  final ChatController chatController;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  AppSection _section = AppSection.chat;

  TeamController get controller => widget.controller;
  ChatController get chatController => widget.chatController;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleControllerChanged);
    chatController.addListener(_handleControllerChanged);
    final selected = controller.selectedTeam;
    if (selected != null) {
      chatController.syncTeam(selected);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    chatController.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final selected = controller.selectedTeam;
    if (selected != null) {
      chatController.syncTeam(selected);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedTeam;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            AppRail(
              selected: _section,
              onSelected: (section) => setState(() => _section = section),
            ),
            ContextSidebar(
              controller: controller,
              selectedSectionLabel:
                  _section == AppSection.config ? 'Config' : 'Chat',
            ),
            if (selected == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_section == AppSection.config)
              WorkspaceShell(
                breadcrumb: 'Config / Overview',
                title: 'Configuration',
                subtitle: 'Team, Member, Layout, and LLM configuration',
                actions: const [],
                child: const ConfigWorkspace(),
              )
            else
              WorkspaceShell(
                breadcrumb: '${selected.name} / Chat / Shell chat workbench',
                title: 'Shell chat workbench',
                subtitle:
                    'target: ${chatController.selectedMemberName(selected)} / shell wrapper mode',
                actions: [
                  FilledButton.tonalIcon(
                    key: AppKeys.openTeamLeadButton,
                    onPressed: controller.isLaunching
                        ? null
                        : () => _openTeamLead(selected),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Open team-lead'),
                  ),
                  FilledButton.icon(
                    key: AppKeys.openTeamButton,
                    onPressed: controller.isLaunching
                        ? null
                        : controller.launchSelectedTeam,
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Open Team'),
                  ),
                ],
                child: ChatWorkbench(
                  team: selected,
                  chatController: chatController,
                ),
                rightTools: RightToolsPanel(
                  team: selected,
                  teamController: controller,
                  chatController: chatController,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTeamLead(TeamConfig team) async {
    final lead = team.members.where((member) => member.name == 'team-lead');
    if (lead.isEmpty) {
      chatController.addSystemMessage(
        team.id,
        'FlashskyAI requires a member named team-lead before opening the team lead.',
      );
      return;
    }
    await controller.launchMember(lead.first.id);
    chatController.addSystemMessage(team.id, controller.statusMessage);
  }
}
```

Remove the old private editor/sidebar widget classes from `main.dart` after the new widgets compile.

- [ ] **Step 6: Run widget tests and fix compile errors**

Run:

```bash
cd client && flutter test test/widget_test.dart
```

Expected: still FAIL because `ChatWorkbench` and `RightToolsPanel` are not implemented yet. Compilation errors should only reference those missing files/classes.

## Task 4: Chat Workbench and Right Tools

**Files:**

- Create: `client/lib/widgets/chat_workbench.dart`
- Create: `client/lib/widgets/right_tools_panel.dart`
- Modify: `client/test/widget_test.dart`

- [ ] **Step 1: Create chat workbench widget**

Create `client/lib/widgets/chat_workbench.dart`:

```dart
import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../chat_controller.dart';
import '../chat_models.dart';
import '../team_config.dart';

class ChatWorkbench extends StatefulWidget {
  const ChatWorkbench({
    required this.team,
    required this.chatController,
    super.key,
  });

  final TeamConfig team;
  final ChatController chatController;

  @override
  State<ChatWorkbench> createState() => _ChatWorkbenchState();
}

class _ChatWorkbenchState extends State<ChatWorkbench> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.chatController.messages
        .where((message) => message.teamId == widget.team.id)
        .toList(growable: false);
    return Container(
      key: AppKeys.chatWorkspace,
      color: const Color(0xFF090D13),
      child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const _EmptyTimeline()
                : ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: messages[index]),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1017),
              border: Border(top: BorderSide(color: Color(0x2E94A3B8))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'To: ${widget.chatController.selectedMemberName(widget.team)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      key: AppKeys.copyPromptButton,
                      tooltip: 'Copy prompt',
                      onPressed: _copyPrompt,
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton.filled(
                      key: AppKeys.sendPromptButton,
                      tooltip: 'Send prompt',
                      onPressed: _sendPrompt,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: AppKeys.chatInput,
                  controller: _inputController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Write a prompt for team-lead...',
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPrompt() async {
    await widget.chatController.submitPrompt(widget.team, _inputController.text);
    _inputController.clear();
  }

  Future<void> _copyPrompt() async {
    await widget.chatController.submitPrompt(widget.team, _inputController.text);
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Local shell-mode conversation notes will appear here.',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.54)),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final isSystem = message.role == ChatMessageRole.system;
    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : isSystem
              ? Alignment.center
              : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF1D4ED8)
              : isSystem
                  ? const Color(0x1F94A3B8)
                  : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(9),
          border: isUser
              ? null
              : Border.all(color: const Color(0x3394A3B8)),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isSystem ? Colors.white.withValues(alpha: 0.68) : null,
            fontSize: isSystem ? 12 : 14,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create right tools widget**

Create `client/lib/widgets/right_tools_panel.dart`:

```dart
import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../chat_controller.dart';
import '../team_config.dart';
import '../team_controller.dart';

class RightToolsPanel extends StatelessWidget {
  const RightToolsPanel({
    required this.team,
    required this.teamController,
    required this.chatController,
    super.key,
  });

  final TeamConfig team;
  final TeamController teamController;
  final ChatController chatController;

  @override
  Widget build(BuildContext context) {
    final members = [...team.members]..sort((a, b) {
        if (a.name == 'team-lead') return -1;
        if (b.name == 'team-lead') return 1;
        return 0;
      });
    return Container(
      key: AppKeys.rightToolsPanel,
      width: 320,
      color: const Color(0xFF10141B),
      child: Column(
        children: [
          Expanded(
            flex: 42,
            child: _MembersPanel(
              members: members,
              selectedMemberId: chatController.selectedMemberId,
              onSelected: chatController.selectMember,
              onOpen: teamController.launchMember,
            ),
          ),
          const Divider(height: 1, color: Color(0x2E94A3B8)),
          Expanded(flex: 58, child: _FileTreePanel(team: team)),
        ],
      ),
    );
  }
}

class _MembersPanel extends StatelessWidget {
  const _MembersPanel({
    required this.members,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onOpen,
  });

  final List<TeamMemberConfig> members;
  final String selectedMemberId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: AppKeys.membersPanel,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelTitle(title: 'Members', action: 'Open Team'),
          Expanded(
            child: ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                final selected = member.id == selectedMemberId;
                return Container(
                  key: AppKeys.memberRow(member.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: selected
                        ? const Color(0x2E064E3B)
                        : const Color(0x9E0F172A),
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      title: Text(member.name),
                      subtitle: Text(
                        [
                          member.provider,
                          member.model,
                        ].where((value) => value.isNotEmpty).join(' / '),
                      ),
                      trailing: IconButton(
                        key: AppKeys.memberOpenButton(member.id),
                        tooltip: 'Open member',
                        onPressed: () => onOpen(member.id),
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                      onTap: () => onSelected(member.id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTreePanel extends StatelessWidget {
  const _FileTreePanel({required this.team});

  final TeamConfig team;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: AppKeys.fileTreePanel,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelTitle(title: 'File Tree', action: 'copy'),
          const SizedBox(height: 8),
          const TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter files',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            team.workingDirectory,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.56),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          const _FileLine(icon: Icons.folder_outlined, label: 'client'),
          const _FileLine(icon: Icons.folder_outlined, label: 'docs'),
          const _FileLine(icon: Icons.description_outlined, label: 'README.md'),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, required this.action});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Text(action, style: const TextStyle(color: Color(0xFF93C5FD))),
      ],
    );
  }
}

class _FileLine extends StatelessWidget {
  const _FileLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Add prompt submission widget test**

Add to `client/test/widget_test.dart`:

```dart
testWidgets('sending a prompt adds local user and system messages', (
  tester,
) async {
  final controller = await createController();

  await tester.pumpWidget(FlashskyAiClientApp(controller: controller));
  await tester.enterText(find.byKey(AppKeys.chatInput), 'Continue the plan');
  await tester.tap(find.byKey(AppKeys.sendPromptButton));
  await tester.pumpAndSettle();

  expect(find.text('Continue the plan'), findsOneWidget);
  expect(
    find.text(
      'Copied prompt for team-lead. Paste it into the FlashskyAI terminal.',
    ),
    findsOneWidget,
  );
});
```

- [ ] **Step 4: Add member target selection widget test**

Add to `client/test/widget_test.dart`:

```dart
testWidgets('selecting a member changes the composer target', (tester) async {
  final controller = await createController();
  await controller.addMember();
  final member = controller.selectedTeam!.members.last;

  await tester.pumpWidget(FlashskyAiClientApp(controller: controller));
  await tester.tap(find.byKey(AppKeys.memberRow(member.id)));
  await tester.pumpAndSettle();

  expect(find.text('To: New Member'), findsOneWidget);
});
```

- [ ] **Step 5: Run widget tests and verify they pass**

Run:

```bash
cd client && flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add client/lib/app_keys.dart client/lib/main.dart client/lib/widgets client/test/widget_test.dart
git commit -m "feat: add workspace chat shell"
```

## Task 5: Preserve Launch Semantics in the New UI

**Files:**

- Modify: `client/test/widget_test.dart`
- Modify: `client/lib/widgets/right_tools_panel.dart`
- Modify: `client/lib/main.dart`

- [ ] **Step 1: Update existing launch widget tests**

Keep or add these tests in `client/test/widget_test.dart`:

```dart
testWidgets('member open button launches one member from right panel', (
  tester,
) async {
  TeamMemberConfig? launchedMember;
  final controller = await createController(
    launcher: (_, member) async {
      launchedMember = member;
    },
  );
  final member = controller.selectedTeam!.members.single;

  await tester.pumpWidget(FlashskyAiClientApp(controller: controller));
  await tester.tap(find.byKey(AppKeys.memberOpenButton(member.id)));
  await tester.pumpAndSettle();

  expect(launchedMember?.name, 'team-lead');
});

testWidgets('open team button launches all members', (tester) async {
  final launched = <String>[];
  final controller = await createController(
    launcher: (_, member) async {
      launched.add(member.name);
    },
  );
  await controller.addMember();

  await tester.pumpWidget(FlashskyAiClientApp(controller: controller));
  await tester.tap(find.byKey(AppKeys.openTeamButton));
  await tester.pumpAndSettle();

  expect(launched, ['team-lead', 'New Member']);
});
```

- [ ] **Step 2: Run launch widget tests and verify failure if any**

Run:

```bash
cd client && flutter test test/widget_test.dart
```

Expected: PASS. If it fails because a button is off-screen, wrap the tap target with `tester.ensureVisible(...)` before tapping.

- [ ] **Step 3: Add team-lead missing behavior test**

Add to `client/test/widget_test.dart`:

```dart
testWidgets('open team-lead shows local status when team-lead is missing', (
  tester,
) async {
  final controller = await createController();
  final selected = controller.selectedTeam!;
  await controller.updateSelected(
    selected.copyWith(
      members: const [TeamMemberConfig(id: 'coder', name: 'coder')],
    ),
  );

  await tester.pumpWidget(FlashskyAiClientApp(controller: controller));
  await tester.tap(find.byKey(AppKeys.openTeamLeadButton));
  await tester.pumpAndSettle();

  expect(
    find.text(
      'FlashskyAI requires a member named team-lead before opening the team lead.',
    ),
    findsOneWidget,
  );
});
```

- [ ] **Step 4: Run focused tests and verify pass**

Run:

```bash
cd client && flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add client/lib/main.dart client/lib/widgets/right_tools_panel.dart client/test/widget_test.dart
git commit -m "test: preserve launch behavior in workbench"
```

## Task 6: Full Verification

**Files:**

- No source files unless verification reveals issues.

- [ ] **Step 1: Run all Flutter tests**

Run:

```bash
cd client && flutter test
```

Expected: all tests pass.

- [ ] **Step 2: Run static analysis**

Run:

```bash
cd client && flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Run Linux debug build**

Run:

```bash
cd client && flutter build linux --debug
```

Expected: build succeeds.

- [ ] **Step 4: Commit verification fixes if needed**

If verification required fixes, commit them:

```bash
git add client
git commit -m "fix: pass workspace shell verification"
```

If no fixes were needed, do not create an empty commit.

## Self-Review

Spec coverage:

- Corrected workspace chrome: Task 3.
- Topbar spans center and right tools, not app rail/context sidebar: Task 3.
- Chat shell behavior with truthful copied status: Tasks 1 and 4.
- Right-side Members above File Tree: Task 4.
- Config page without chat right tools: Tasks 2 and 3.
- Existing launch behavior preserved: Task 5.

Intentional gaps deferred to later plans:

- Full Team Config editor.
- Full Member Config editor.
- Full LLM Config editor.
- Drag-resizable persisted sizing.
- Real FlashskyAI streaming/native bridge.

Placeholder scan:

- This plan contains no incomplete-work markers.
- Every code-bearing task includes concrete file paths, commands, and expected outcomes.

Type consistency:

- `AppKeys` is moved to `client/lib/app_keys.dart` and imported by both UI and tests.
- `ChatController` constructor accepts `ClipboardWriter`, matching the tests.
- `WorkspaceShell` takes an optional `rightTools`, matching the corrected UI architecture.

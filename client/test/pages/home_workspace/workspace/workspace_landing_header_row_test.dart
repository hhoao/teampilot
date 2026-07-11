import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_selectors.dart';
import 'package:teampilot/widgets/menu/sidebar_action_menu.dart';

void main() {
  testWidgets(
    'WorkspaceLandingHeaderRow does not overflow in narrow width',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 191,
              child: WorkspaceLandingHeaderRow(
                projectLabel: 'very-long-project-directory-name',
                projectHintWhenEmpty: 'Select project',
                projectMenuSpecs: const [
                  SidebarActionMenuSpec.item(
                    value: '/project',
                    icon: Icons.folder_outlined,
                    label: 'very-long-project-directory-name',
                  ),
                ],
                onProjectSelected: (_) {},
                showWorktreeSelector: true,
                worktreeLabel: 'feature/very-long-branch-name',
                worktreeHintWhenEmpty: 'Select worktree',
                worktreeMenuSpecs: const [
                  SidebarActionMenuSpec.item(
                    value: '/worktree',
                    icon: Icons.account_tree_outlined,
                    label: 'feature/very-long-branch-name',
                  ),
                ],
                onWorktreeSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_selectors.dart';
import 'package:shared_ui/shared_ui.dart';
Widget _header({
  required double width,
  required String projectLabel,
  required String worktreeLabel,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: WorkspaceLandingHeaderRow(
          projectLabel: projectLabel,
          projectHintWhenEmpty: 'Select project',
          projectMenuSpecs: [
            TpActionMenuSpec.item(
              value: '/project',
              icon: Icons.folder_outlined,
              label: projectLabel,
            ),
          ],
          onProjectSelected: (_) {},
          showWorktreeSelector: true,
          worktreeLabel: worktreeLabel,
          worktreeHintWhenEmpty: 'Select worktree',
          worktreeMenuSpecs: [
            TpActionMenuSpec.item(
              value: '/worktree',
              icon: Icons.account_tree_outlined,
              label: worktreeLabel,
            ),
          ],
          onWorktreeSelected: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'WorkspaceLandingHeaderRow does not overflow in narrow width',
    (tester) async {
      await tester.pumpWidget(
        _header(
          width: 191,
          projectLabel: 'very-long-project-directory-name',
          worktreeLabel: 'feature/very-long-branch-name',
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'WorkspaceLandingHeaderRow keeps selectors left-aligned',
    (tester) async {
      await tester.pumpWidget(
        _header(
          width: 600,
          projectLabel: 'proj',
          worktreeLabel: 'main',
        ),
      );
      await tester.pumpAndSettle();

      final project = tester.getTopLeft(find.text('proj'));
      final worktree = tester.getTopLeft(find.text('main'));

      expect(project.dx, lessThan(24));
      // Adjacent chips — not split across half the row (~300px).
      expect(worktree.dx - project.dx, lessThan(120));
    },
  );
}

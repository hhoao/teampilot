import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope_registry.dart';

import '../../support/test_runtime_context.dart';

void main() {
  testWidgets(
    'cubitFor from build does not mark a peer ListenableBuilder dirty',
    (tester) async {
      final home = testRuntimeContext('/home');
      final lifecycle = SessionLifecycleService(
        storageRootsResolver: () async => home,
        workContextResolver: (_) async => home,
      );
      final registry = WorkspaceToolsScopeRegistry();
      addTearDown(registry.dispose);

      var listenableBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableProvider<WorkspaceToolsScopeRegistry>.value(
            value: registry,
            child: Column(
              children: [
                // A peer listener outside the resolving subtree, mirroring the
                // floating-workspace scope bridge.
                ListenableBuilder(
                  listenable: registry,
                  builder: (context, _) {
                    listenableBuilds++;
                    return const SizedBox(width: 1, height: 1);
                  },
                ),
                _ResolveScopeDuringBuild(
                  tabScopeId: 'ws-1',
                  lifecycle: lifecycle,
                ),
              ],
            ),
          ),
        ),
      );

      // A registration from build must not explode the build phase; the
      // deferred announcement arrives after the frame.
      expect(tester.takeException(), isNull);
      expect(listenableBuilds, 1);
      await tester.pump();
      // The peer listener re-resolves on the following frame.
      expect(listenableBuilds, 2);
    },
  );
}

class _ResolveScopeDuringBuild extends StatelessWidget {
  const _ResolveScopeDuringBuild({
    required this.tabScopeId,
    required this.lifecycle,
  });

  final String tabScopeId;
  final SessionLifecycleService lifecycle;

  @override
  Widget build(BuildContext context) {
    // Mirrors WorkspaceSplitPane resolving its scope cubit during build.
    context.read<WorkspaceToolsScopeRegistry>().cubitFor(
      tabScopeId: tabScopeId,
      lifecycle: lifecycle,
    );
    return const SizedBox(width: 1, height: 1);
  }
}
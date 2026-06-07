import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell.dart';

Widget _wrapShell(Widget shell) {
  return MaterialApp(
    home: BlocProvider(
      create: (_) => LayoutCubit(),
      child: Scaffold(body: shell),
    ),
  );
}

void main() {
  testWidgets('workspace shell renders child without transition animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapShell(
        const WorkspaceShell(
          showHeader: false,
          breadcrumb: 'Team / Chat',
          title: 'Chat',
          subtitle: 'Terminal',
          actions: [],
          child: Text('Terminal body'),
        ),
      ),
    );

    expect(find.text('Terminal body'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });
}

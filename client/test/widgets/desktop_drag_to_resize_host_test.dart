import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/desktop_drag_to_resize_host.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets('toggling expanded keeps DragToResizeArea and child State', (
    tester,
  ) async {
    _MountProbeState.mounts = 0;

    await tester.pumpWidget(
      const MaterialApp(home: DesktopDragToResizeHost(child: _MountProbe())),
    );
    expect(find.byType(DragToResizeArea), findsOneWidget);
    expect(
      tester
          .widget<DragToResizeArea>(find.byType(DragToResizeArea))
          .enableResizeEdges,
      isNull,
    );
    expect(find.text('mounts:1'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopDragToResizeHost(expanded: true, child: _MountProbe()),
      ),
    );
    expect(find.byType(DragToResizeArea), findsOneWidget);
    expect(
      tester
          .widget<DragToResizeArea>(find.byType(DragToResizeArea))
          .enableResizeEdges,
      isEmpty,
    );
    expect(find.text('mounts:1'), findsOneWidget);
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe();

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  static int mounts = 0;

  @override
  void initState() {
    super.initState();
    mounts++;
  }

  @override
  Widget build(BuildContext context) => Text('mounts:$mounts');
}

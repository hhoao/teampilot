import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workbench/file_editor_image_preview.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

// 1x1 transparent PNG (same fixture as markdown_preview_svg_image_test.dart).
final pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('renders bitmap bytes through PhotoView with zoom toolbar',
      (tester) async {
    // Real filesystem I/O must run inside runAsync in widget tests
    // (same convention as test/smoke/app_shell_smoke_test.dart).
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tp_image_preview'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    final png = File('${dir.path}/a.png')..writeAsBytesSync(pngBytes);

    final editor = EditorCubit(fs: LocalFilesystem());
    addTearDown(editor.close);
    await tester.runAsync(() => editor.openFile('ws', png.path));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<EditorCubit>.value(
            value: editor,
            child: FileEditorImagePreview(workspaceId: 'ws', path: png.path),
          ),
        ),
      ),
    );
    // Bounded pumps instead of pumpAndSettle: PhotoView keeps scheduling
    // frames after the contained-scale-to-1:1 clamp, which never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PhotoView), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });
}

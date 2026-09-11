import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/markdown_preview_link_handler.dart';
import 'package:tp_markdown/tp_markdown.dart';

Future<File> _writeRasterPng(String path, {int size = 200}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 200),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  return File(path).writeAsBytes(bytes.buffer.asUint8List());
}

void main() {
  // Mirrors teampilot README.md image structures.
  const source = '''
<p align="center">
  <img src="assets/icon.svg" alt="TeamPilot" width="100"/>
</p>
<div align="center">
  <a href="https://github.com/hhoao/teampilot/releases"><img src="https://img.shields.io/github/v/release/hhoao/teampilot?logo=github&label=Release" alt="Release"></a>
</div>
<p align="center">
  <img src="./assets/readme-overview-1.png" style="width: 70%" alt="overview" />
  <img src="./assets/chat.jpg" style="width: 19%" alt="chat" />
</p>
<p align="center">
  <img src="./assets/readme-qq-qrcode.jpg" alt="qrcode" width="220"/>
</p>
''';
  final doc = compileMarkdown(source);

  // Serve local raster files from temp dir.
  late Directory dir;

  ImageProvider? resolve(String src) => resolveMarkdownPreviewImage(
        src: src,
        markdownFilePath: '${dir.path}/README.md',
        workspaceRoots: [dir.path],
      );

  Widget? resolveWidget(String src, {required bool inline, required double? inlineHeight}) =>
      buildMarkdownPreviewImage(
        src: src,
        markdownFilePath: '${dir.path}/README.md',
        workspaceRoots: [dir.path],
        inline: inline,
        inlineHeight: inlineHeight,
      );

  testWidgets('README image structures render with browser-like sizing', (
    tester,
  ) async {
    dir = Directory.systemTemp.createTempSync('readme-structure');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Real 200x200 raster: contain-fit must fill the hinted width boxes
    // (a 1x1 stub would keep intrinsic size and defeat the assertions).
    Directory('${dir.path}/assets').createSync();
    await tester.runAsync(() async {
      for (final name in [
        'readme-overview-1.png',
        'chat.jpg',
        'readme-qq-qrcode.jpg',
      ]) {
        await _writeRasterPng('${dir.path}/assets/$name');
      }
    });
    File('${dir.path}/assets/icon.svg').writeAsStringSync(
      '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">'
      '<rect width="512" height="512" fill="#555"/></svg>',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: SingleChildScrollView(
            child: VirtualMarkdownView(
              document: doc,
              tokens: MarkdownTokens.test(),
              resolvers: MarkdownResolvers(
                resolveImage: resolve,
                buildImageWidget: resolveWidget as Widget? Function(
                  String, {
                  required bool inline,
                  required double inlineHeight,
                })?,
              ),
              flatten: true,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Badge row: shields urls go through the widget hook (no NetworkImage).
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.where((i) => i.image is NetworkImage), isEmpty);

    // Block figures render at their hinted widths, not the 19.6px line box:
    // each hinted img's own render box carries its width (parent SizedBox
    // constraints), and none keep the inline line-box height clamp.
    final hintedSizes = <double>[];
    for (final entry in tester.widgetList<Image>(find.byType(Image))) {
      final size = tester.getSize(find.byWidget(entry));
      if (entry.height != null) continue; // inline badge (line-clamped)
      hintedSizes.add(size.width);
    }
    hintedSizes.sort();
    // 19% and 70% of the ~784px paragraph box, plus the 220px qrcode.
    expect(hintedSizes, contains(closeTo(220, 2)), reason: 'qrcode width hint');
    expect(hintedSizes.where((w) => w > 130 && w < 200).length, greaterThan(0),
        reason: '19% column width');
    expect(hintedSizes.where((w) => w > 500).length, greaterThan(0),
        reason: '70% column width');
    // No image rendered below 100px wide (line-clamped or zero-height path).
    expect(hintedSizes.every((w) => w > 100), isTrue);
  });
}

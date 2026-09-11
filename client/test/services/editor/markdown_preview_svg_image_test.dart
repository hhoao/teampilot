import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:teampilot/services/editor/markdown_preview_link_handler.dart';
import 'package:teampilot/widgets/workbench/markdown_network_image.dart';

const badgeSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="20" '
    'role="img" aria-label="license: AGPL-3.0"><title>license: AGPL-3.0</title>'
    '<linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" '
    'stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient>'
    '<clipPath id="r"><rect width="108" height="20" rx="3" fill="#fff"/></clipPath>'
    '<g clip-path="url(#r)"><rect width="108" height="20" fill="#555"/>'
    '<rect x="63" width="45" height="20" fill="#007ec6"/>'
    '<rect width="108" height="20" fill="url(#s)"/></g>'
    '<g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" '
    'font-size="110"><text x="32.5" y="150" fill="#010101" fill-opacity=".3" '
    'transform="scale(.1)" textLength="580">license</text>'
    '<text x="32.5" y="140" textLength="580">license</text></g></svg>';

// 1x1 transparent PNG.
final pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget harness(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('preferRasterBadgeUrl', () {
    test('rewrites shields.io to PNG (logos + social stars need raster)', () {
      // flutter_svg drops <image href="data:image/svg+xml;base64,…"> logos
      // and mishandles social-style font-size="110px" + scale(.1) text.
      expect(
        preferRasterBadgeUrl(
          Uri.parse(
            'https://img.shields.io/github/stars/hhoao/teampilot?logo=github&label=Stars',
          ),
        ).toString(),
        'https://img.shields.io/github/stars/hhoao/teampilot.png?logo=github&label=Stars',
      );
      expect(
        preferRasterBadgeUrl(
          Uri.parse(
            'https://img.shields.io/github/v/release/hhoao/teampilot?logo=github&label=Release',
          ),
        ).toString(),
        'https://img.shields.io/github/v/release/hhoao/teampilot.png?logo=github&label=Release',
      );
      expect(
        preferRasterBadgeUrl(
          Uri.parse('https://img.shields.io/badge/license-AGPL--3.0-blue.svg'),
        ).toString(),
        'https://img.shields.io/badge/license-AGPL--3.0-blue.png',
      );
    });

    test('appends .png even when badge label contains a domain-like dot', () {
      // Regression: path segment `官网-restcut.com-00C1D4` contains `.` so the
      // old "has extension" check skipped PNG rewrite; SVG then dropped the
      // safari <image href="data:…"> logo.
      final out = preferRasterBadgeUrl(
        Uri.parse(
          'https://img.shields.io/badge/官网-restcut.com-00C1D4?logo=safari&logoColor=white',
        ),
      );
      expect(out.path, endsWith('.png'));
      expect(out.queryParameters['logo'], 'safari');
      expect(
        out.pathSegments.last.toLowerCase().endsWith('.png'),
        isTrue,
      );
    });

    test('leaves non-shields URLs alone', () {
      expect(
        preferRasterBadgeUrl(
          Uri.parse(
            'https://github.com/hhoao/teampilot/actions/workflows/client-verify.yml/badge.svg',
          ),
        ).toString(),
        'https://github.com/hhoao/teampilot/actions/workflows/client-verify.yml/badge.svg',
      );
    });
  });

  group('normalizeShieldsBadgeSvg', () {
    const shieldsLicenseSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="20">'
        '<filter id="blur"><feGaussianBlur stdDeviation="16"/></filter>'
        '<g fill="#fff" font-size="110">'
        '<g transform="scale(.1)">'
        '<text x="245" y="140" textLength="370">license</text>'
        '</g>'
        '<g transform="scale(.1)">'
        '<text x="765" y="140" textLength="510">AGPL-3.0</text>'
        '</g>'
        '</g></svg>';

    test('flattens font-size 110 + scale(.1) text into 1x coordinates', () {
      final out = normalizeShieldsBadgeSvg(shieldsLicenseSvg);
      expect(out.contains('font-size="110"'), isFalse);
      expect(out.contains('font-size="11"'), isTrue);
      expect(out.contains('scale(.1)'), isFalse);
      expect(out.contains('stdDeviation="1.6"'), isTrue);
      expect(out.contains('width="108"'), isTrue);
      expect(out.contains('x="24.5"'), isTrue);
      expect(out.contains('y="14"'), isTrue);
      expect(out.contains('textLength="37"'), isTrue);
    });

    test('flattens social-style font-size 110px on text transforms', () {
      const social =
          '<svg xmlns="http://www.w3.org/2000/svg" width="82" height="20">'
          '<g font-size="110px">'
          '<text x="355" y="140" transform="scale(.1)" textLength="270">Stars</text>'
          '</g></svg>';
      final out = normalizeShieldsBadgeSvg(social);
      expect(out.contains('font-size="110px"'), isFalse);
      expect(out.contains('font-size="11px"'), isTrue);
      expect(out.contains('scale(.1)'), isFalse);
      expect(out.contains('x="35.5"'), isTrue);
    });

    test('leaves non-shields svg unchanged', () {
      const plain =
          '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
          '<text x="5" y="8" font-size="11">ok</text></svg>';
      expect(normalizeShieldsBadgeSvg(plain), plain);
    });
  });

  group('buildMarkdownPreviewImage http routing', () {
    test('extensionless shields URL fetches PNG via sniffing widget', () {
      final widget = buildMarkdownPreviewImage(
        src:
            'https://img.shields.io/github/stars/hhoao/teampilot?logo=github&label=Stars',
        markdownFilePath: '/repo/README.md',
        workspaceRoots: const ['/repo'],
      );

      expect(widget, isA<MarkdownNetworkImage>());
      expect(
        (widget! as MarkdownNetworkImage).url,
        'https://img.shields.io/github/stars/hhoao/teampilot.png?logo=github&label=Stars',
      );
    });

    test('shields .svg URL is rewritten to PNG', () {
      final widget = buildMarkdownPreviewImage(
        src: 'https://img.shields.io/badge/license-AGPL--3.0-blue.svg',
        markdownFilePath: '/repo/README.md',
        workspaceRoots: const ['/repo'],
      );

      expect(widget, isA<MarkdownNetworkImage>());
      expect(
        (widget! as MarkdownNetworkImage).url,
        'https://img.shields.io/badge/license-AGPL--3.0-blue.png',
      );
    });

    test('non-shields .svg URL keeps original via sniffing widget', () {
      final widget = buildMarkdownPreviewImage(
        src:
            'https://github.com/hhoao/teampilot/actions/workflows/client-verify.yml/badge.svg',
        markdownFilePath: '/repo/README.md',
        workspaceRoots: const ['/repo'],
      );

      expect(widget, isA<MarkdownNetworkImage>());
      expect(
        (widget! as MarkdownNetworkImage).url,
        'https://github.com/hhoao/teampilot/actions/workflows/client-verify.yml/badge.svg',
      );
    });

    test('resolveMarkdownPreviewImage returns null for http URLs', () {
      expect(
        resolveMarkdownPreviewImage(
          src: 'https://img.shields.io/github/stars/hhoao/teampilot',
          markdownFilePath: '/repo/README.md',
          workspaceRoots: const ['/repo'],
        ),
        isNull,
      );
      expect(
        resolveMarkdownPreviewImage(
          src: 'https://example.com/photo.png',
          markdownFilePath: '/repo/README.md',
          workspaceRoots: const ['/repo'],
        ),
        isNull,
      );
    });

    test('inline http image is capped to the line box (no upscale)', () {
      final widget = buildMarkdownPreviewImage(
        src: 'https://img.shields.io/badge/x.svg',
        markdownFilePath: '/repo/README.md',
        workspaceRoots: const ['/repo'],
        inline: true,
        inlineHeight: 28,
      );

      final box = widget! as ConstrainedBox;
      expect(box.constraints.maxHeight, 28);
      expect(box.constraints.minHeight, 0);
      expect(box.child, isA<MarkdownNetworkImage>());
      expect(
        (box.child! as MarkdownNetworkImage).url,
        'https://img.shields.io/badge/x.png',
      );
    });

    test('workspace .svg file returns SvgPicture.file', () {
      final dir = Directory.systemTemp.createTempSync('md-preview-svg');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svgPath = [dir.path, 'logo.svg'].join(Platform.pathSeparator);
      File(svgPath).writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"/>',
      );
      final md = [dir.path, 'a.md'].join(Platform.pathSeparator);

      final widget = buildMarkdownPreviewImage(
        src: './logo.svg',
        markdownFilePath: md,
        workspaceRoots: [dir.path],
      );

      expect(widget, isA<SvgPicture>());
      final loader = (widget! as SvgPicture).bytesLoader;
      expect(loader, isA<SvgFileLoader>());
      expect((loader as SvgFileLoader).file.path, svgPath);
    });

    test('workspace .svg missing on disk returns null', () {
      final dir = Directory.systemTemp.createTempSync('md-preview-svg-miss');
      addTearDown(() => dir.deleteSync(recursive: true));
      final md = [dir.path, 'a.md'].join(Platform.pathSeparator);

      expect(
        buildMarkdownPreviewImage(
          src: './missing.svg',
          markdownFilePath: md,
          workspaceRoots: [dir.path],
        ),
        isNull,
      );
    });
  });

  group('MarkdownNetworkImage sniffing', () {
    testWidgets('renders SVG served without content-type hint', (
      tester,
    ) async {
      await tester.pumpWidget(harness(MarkdownNetworkImage(
        url: 'https://img.shields.io/github/stars/x',
        fetch: (uri) async => http.Response.bytes(
          Uint8List.fromList(badgeSvg.codeUnits),
          200,
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders SVG reported by content-type only', (
      tester,
    ) async {
      await tester.pumpWidget(harness(MarkdownNetworkImage(
        url: 'https://img.shields.io/badge/a',
        fetch: (uri) async => http.Response.bytes(
          Uint8List.fromList(badgeSvg.codeUnits),
          200,
          headers: {'content-type': 'image/svg+xml; charset=utf-8'},
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders raster PNG payloads as Image', (tester) async {
      await tester.pumpWidget(harness(MarkdownNetworkImage(
        url: 'https://example.com/photo',
        fetch: (uri) async => http.Response.bytes(
          pngBytes,
          200,
          headers: {'content-type': 'image/png'},
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('non-200 collapses to shrink without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(harness(MarkdownNetworkImage(
        url: 'https://example.com/404',
        fetch: (uri) async => http.Response('missing', 404),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fetch failure collapses to shrink without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(harness(MarkdownNetworkImage(
        url: 'https://example.com/error',
        fetch: (uri) async => throw Exception('network down'),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('normalized shields svg keeps intrinsic 108x20 size', (
      tester,
    ) async {
      const modernShieldsSvg =
          '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="20">'
          '<filter id="blur"><feGaussianBlur stdDeviation="16"/></filter>'
          '<rect width="108" height="20" fill="#555"/>'
          '<g fill="#fff" font-size="110">'
          '<g transform="scale(.1)">'
          '<text x="245" y="140" textLength="370">license</text>'
          '</g></g></svg>';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: Align(
                alignment: Alignment.topLeft,
                child: MarkdownNetworkImage(
                  url: 'https://img.shields.io/badge/license-blue',
                  fetch: (uri) async => http.Response(
                    modernShieldsSvg,
                    200,
                    headers: {'content-type': 'image/svg+xml'},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SvgPicture));
      expect(size.width, closeTo(108, 2));
      expect(size.height, closeTo(20, 2));
      expect(tester.takeException(), isNull);
    });
  });

  group('SvgPicture smoke (real shields.io badge markup)', () {
    testWidgets('renders through the file widget path', (tester) async {
      // flutter test's HttpClient mock returns empty 400s, so the network
      // loader cannot be exercised here; the file loader shares the same
      // SvgLoader._load → encodeSvg pipeline.
      final dir = Directory.systemTemp.createTempSync('md-preview-svg-smoke');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svgPath = [dir.path, 'badge.svg'].join(Platform.pathSeparator);
      File(svgPath).writeAsStringSync(badgeSvg);
      final md = [dir.path, 'a.md'].join(Platform.pathSeparator);

      final widget = buildMarkdownPreviewImage(
        src: './badge.svg',
        markdownFilePath: md,
        workspaceRoots: [dir.path],
      );
      expect(widget, isNotNull);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('block badge keeps intrinsic size (no upscale)', (
      tester,
    ) async {
      // Regression: BoxFit.contain upscaled a 108x20 badge to the full
      // column width under loose block constraints.
      final dir = Directory.systemTemp.createTempSync('md-preview-svg-size');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svgPath = [dir.path, 'badge.svg'].join(Platform.pathSeparator);
      File(svgPath).writeAsStringSync(badgeSvg);
      final md = [dir.path, 'a.md'].join(Platform.pathSeparator);

      final widget = buildMarkdownPreviewImage(
        src: './badge.svg',
        markdownFilePath: md,
        workspaceRoots: [dir.path],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: Align(
                alignment: Alignment.topLeft,
                child: widget,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SvgPicture));
      expect(size.width, closeTo(108, 2));
      expect(size.height, closeTo(20, 2));
    });

    testWidgets('oversized svg clamps to available width', (tester) async {
      final dir = Directory.systemTemp.createTempSync('md-preview-svg-wide');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svgPath = [dir.path, 'wide.svg'].join(Platform.pathSeparator);
      File(svgPath).writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="2560" height="1556">'
        '<rect width="2560" height="1556" fill="#555"/></svg>',
      );
      final md = [dir.path, 'a.md'].join(Platform.pathSeparator);

      final widget = buildMarkdownPreviewImage(
        src: './wide.svg',
        markdownFilePath: md,
        workspaceRoots: [dir.path],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: Align(
                alignment: Alignment.topLeft,
                child: widget,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SvgPicture));
      expect(size.width, lessThanOrEqualTo(800));
      expect(size.width, greaterThan(700));
      expect(size.height, closeTo(size.width * 1556 / 2560, 1));
    });
  });
}

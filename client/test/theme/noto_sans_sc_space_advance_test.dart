import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/font_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notoSansSc catalog lists asset faces under Noto Sans SC', () {
    final entry = FontCatalog.entry(FontRole.ui, 'notoSansSc');
    expect(entry.bundledFamily, 'Noto Sans SC');
    expect(entry.assetPaths, isNotEmpty);
    expect(
      entry.assetPaths.every((p) => p.startsWith('google_fonts/NotoSansSC-')),
      isTrue,
    );
  });

  testWidgets('Noto Sans SC FontLoader space advance stays proportional', (
    tester,
  ) async {
    const family = 'Noto Sans SC';
    const size = 20.0;
    final loader = FontLoader(family);
    loader.addFont(rootBundle.load('google_fonts/NotoSansSC-Regular.ttf'));
    await loader.load();

    final style = const TextStyle(fontFamily: family, fontSize: size);
    final without = TextPainter(
      text: TextSpan(text: 'Where', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final withSpace = TextPainter(
      text: TextSpan(text: 'Where ', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final spaceAdv = withSpace.width - without.width;

    // Bundled face is ~0.224em; the Android mismatch was ~1.24em.
    expect(spaceAdv, lessThan(size * 0.5));
    expect(spaceAdv, greaterThan(size * 0.1));
  });
}

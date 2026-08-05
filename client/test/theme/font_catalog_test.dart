import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/font_catalog.dart';

void main() {
  test('default preference ids are bundled faces', () {
    expect(FontCatalog.defaultUiId, 'notoSansSc');
    expect(FontCatalog.defaultMonoId, 'jetbrainsMono');
  });

  test('uiOptions includes system and notoSansSc', () {
    final ids = FontCatalog.uiOptions.map((e) => e.id).toList();
    expect(ids, containsAll(['system', 'notoSansSc']));
  });

  test('monoOptions includes system and jetbrainsMono', () {
    final ids = FontCatalog.monoOptions.map((e) => e.id).toList();
    expect(ids, containsAll(['system', 'jetbrainsMono']));
  });

  test('entry unknown id returns system for that role', () {
    expect(FontCatalog.entry(FontRole.ui, 'nope').id, 'system');
    expect(FontCatalog.entry(FontRole.mono, 'nope').id, 'system');
  });

  test('bundled entries expose family names', () {
    expect(
      FontCatalog.entry(FontRole.ui, 'notoSansSc').bundledFamily,
      isNotEmpty,
    );
    expect(
      FontCatalog.entry(FontRole.mono, 'jetbrainsMono').bundledFamily,
      'JetBrainsMono NFM',
    );
  });
}

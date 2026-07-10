import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor_platform/language_registry.dart';

void main() {
  test('resolves .json to json pack', () {
    expect(LanguageRegistry.builtins().resolve('/x/a.json')?.id, 'json');
  });

  test('scss is plain text this phase', () {
    expect(LanguageRegistry.builtins().resolve('/x/a.scss'), isNull);
  });

  test('resolve is case-insensitive on extension', () {
    expect(LanguageRegistry.builtins().resolve('/x/A.JSON')?.id, 'json');
  });

  test('unknown extension resolves to null', () {
    expect(LanguageRegistry.builtins().resolve('/x/a.unknown'), isNull);
  });

  test('path with no extension resolves to null', () {
    expect(LanguageRegistry.builtins().resolve('/x/Makefile'), isNull);
  });
}

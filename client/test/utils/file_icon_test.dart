import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/file_icon.dart';
import 'package:teampilot/utils/file_icon_mapping.g.dart';

void main() {
  group('fileIconForFileName', () {
    test('matches by extension', () {
      final info = fileIconForFileName('main.dart');
      expect(info.iconName, 'dart');
      expect(info.isLightVariant, isFalse);
    });

    test('matches json extension', () {
      expect(fileIconForFileName('config.json').iconName, 'json');
    });

    test('exact file name beats extension', () {
      // readme.md is mapped to 'readme' by file name, NOT 'md' by extension.
      expect(fileIconForFileName('readme.md').iconName, 'readme');
    });

    test('case-insensitive file name and extension', () {
      expect(fileIconForFileName('README.MD').iconName,
          kFileNameIcons['readme.md']);
      expect(fileIconForFileName('App.DART').iconName, 'dart');
    });

    test('unknown extension falls back to default', () {
      expect(fileIconForFileName('data.xyzunknown').iconName, kDefaultFileIcon);
    });

    test('no extension falls back to default', () {
      expect(fileIconForFileName('zzznoext').iconName, kDefaultFileIcon);
    });

    test('strips path prefix', () {
      expect(fileIconForFileName('lib/src/utils/file_icon.dart').iconName,
          'dart');
    });

    test('light variant flag for known light extension', () {
      // Check light variant flag logic.
      final info = fileIconForFileName('a.blink');
      // If 'blink' is in the extension map, verify the light flag matches.
      if (kFileExtensionIcons.containsKey('blink')) {
        expect(info.iconName, kFileExtensionIcons['blink']);
        expect(info.isLightVariant, kLightFileExtensions.contains('blink'));
      }
    });
  });
}

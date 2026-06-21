import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/workspace_dnd/path_reference_formatter.dart';

void main() {
  const formatter = PathReferenceFormatter();

  group('posixQuoteIfNeeded', () {
    test('leaves a plain path unquoted', () {
      expect(
        formatter.format('/repo/lib/main.dart', PathQuoting.posixQuoteIfNeeded),
        '/repo/lib/main.dart',
      );
    });

    test('quotes a path containing spaces', () {
      expect(
        formatter.format('/repo/my file.txt', PathQuoting.posixQuoteIfNeeded),
        "'/repo/my file.txt'",
      );
    });

    test('escapes embedded single quotes', () {
      expect(
        formatter.format("/repo/a'b.txt", PathQuoting.posixQuoteIfNeeded),
        r"""'/repo/a'\''b.txt'""",
      );
    });

    test('quotes shell-significant characters', () {
      expect(
        formatter.format(r'/repo/a&b.txt', PathQuoting.posixQuoteIfNeeded),
        r"'/repo/a&b.txt'",
      );
    });

    test('leaves a Windows drive path with backslashes unquoted', () {
      expect(
        formatter.format(r'C:\repo\main.dart', PathQuoting.posixQuoteIfNeeded),
        r'C:\repo\main.dart',
      );
    });

    test('empty path becomes empty quotes', () {
      expect(formatter.format('', PathQuoting.posixQuoteIfNeeded), "''");
    });
  });

  test('none emits the path verbatim', () {
    expect(
      formatter.format('/repo/my file.txt', PathQuoting.none),
      '/repo/my file.txt',
    );
  });
}

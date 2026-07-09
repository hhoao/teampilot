import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_trigger_token_edit.dart';

void main() {
  group('composeTokenRangeForBackspace', () {
    test('returns token when cursor is at token end', () {
      const text = 'use /writing-plans';
      final token = composeTokenRangeForBackspace(text, text.length);
      expect(token?.start, 4);
      expect(token?.end, text.length);
    });

    test('returns token when cursor is inside token', () {
      const text = 'use /writing-plans';
      final token = composeTokenRangeForBackspace(text, 9);
      expect(token?.start, 4);
      expect(token?.end, 18);
    });

    test('returns null when cursor is before token', () {
      const text = 'use /writing-plans';
      expect(composeTokenRangeForBackspace(text, 4), isNull);
    });
  });

  group('composeTokenRangeForDelete', () {
    test('returns token when cursor is at token start', () {
      const text = 'use /writing-plans';
      final token = composeTokenRangeForDelete(text, 4);
      expect(token?.start, 4);
      expect(token?.end, 18);
    });

    test('returns null when cursor is at token end', () {
      const text = 'use /writing-plans';
      expect(composeTokenRangeForDelete(text, text.length), isNull);
    });
  });

  group('applyComposeTokenBackspace', () {
    test('deletes whole slash token from end', () {
      const text = 'use /writing-plans';
      final value = const TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

      final updated = applyComposeTokenBackspace(value);
      expect(updated?.text, 'use ');
      expect(updated?.selection.extentOffset, 4);
    });

    test('expands partial selection to full token', () {
      const text = 'use /writing-plans please';
      final value = const TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 8, extentOffset: 14),
      );

      final updated = applyComposeTokenBackspace(value);
      expect(updated?.text, 'use  please');
      expect(updated?.selection.extentOffset, 4);
    });
  });

  group('applyComposeTokenDelete', () {
    test('deletes whole at-token from start', () {
      const text = 'see @src/main.dart next';
      final value = const TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 4),
      );

      final updated = applyComposeTokenDelete(value);
      expect(updated?.text, 'see  next');
      expect(updated?.selection.extentOffset, 4);
    });
  });
}

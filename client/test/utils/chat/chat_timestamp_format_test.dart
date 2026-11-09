import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:teampilot/utils/chat/chat_timestamp_format.dart';

void main() {
  setUpAll(initializeDateFormatting);

  final now = DateTime(2026, 11, 9, 18, 0);

  test('null createdAt returns null', () {
    expect(formatChatTimestamp(null, now: now, locale: 'zh'), isNull);
  });

  test('same local day renders time only', () {
    expect(
      formatChatTimestamp(DateTime(2026, 11, 9, 15, 44), now: now, locale: 'zh'),
      '15:44',
    );
    expect(
      formatChatTimestamp(DateTime(2026, 11, 9, 0, 0), now: now, locale: 'zh'),
      '00:00',
    );
  });

  test('another day renders month-day and time (zh)', () {
    expect(
      formatChatTimestamp(DateTime(2026, 11, 6, 15, 44), now: now, locale: 'zh'),
      '11月6日 15:44',
    );
    // One minute before midnight is still "another day".
    expect(
      formatChatTimestamp(DateTime(2026, 11, 8, 23, 59), now: now, locale: 'zh'),
      '11月8日 23:59',
    );
  });

  test('another day renders month-day and time (en)', () {
    expect(
      formatChatTimestamp(DateTime(2026, 11, 6, 15, 44), now: now, locale: 'en'),
      'Nov 6 15:44',
    );
  });

  test('cross-year stays month-day form without a year', () {
    expect(
      formatChatTimestamp(DateTime(2025, 12, 31, 23, 0), now: now, locale: 'zh'),
      '12月31日 23:00',
    );
  });

  test('UTC input is converted to local time', () {
    final utc = DateTime.utc(2026, 11, 9, 12, 30);
    final local = utc.toLocal();
    // Use a reference day after the converted timestamp so the month-day
    // branch runs; the assertion must reflect the LOCAL month/day and time,
    // not the original UTC values.
    final later = local.add(const Duration(days: 1));
    final expected =
        '${DateFormat('MMMd', 'zh').format(local)} '
        '${DateFormat('HH:mm').format(local)}';
    expect(formatChatTimestamp(utc, now: later, locale: 'zh'), expected);
  });
}

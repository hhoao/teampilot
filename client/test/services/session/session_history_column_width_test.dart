import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/session_history_pagination.dart';

void main() {
  group('resolveSessionHistoryColumnWidth', () {
    test('follows available at or below min width', () {
      expect(resolveSessionHistoryColumnWidth(1080), 1080);
      expect(resolveSessionHistoryColumnWidth(800), 800);
      expect(resolveSessionHistoryColumnWidth(400), 400);
    });

    test('holds min until first jump threshold', () {
      expect(resolveSessionHistoryColumnWidth(1081), 1080);
      expect(resolveSessionHistoryColumnWidth(1479), 1080);
    });

    test('first jump: +400 available → chat 1280', () {
      expect(resolveSessionHistoryColumnWidth(1480), 1280);
      expect(resolveSessionHistoryColumnWidth(1679), 1280);
    });

    test('later jumps clamp at the 1460 ceiling', () {
      expect(resolveSessionHistoryColumnWidth(1680), 1460);
      expect(resolveSessionHistoryColumnWidth(1879), 1460);
      expect(resolveSessionHistoryColumnWidth(1880), 1460);
    });

    test('caps chat width at 1460', () {
      expect(resolveSessionHistoryColumnWidth(1880), 1460);
      expect(resolveSessionHistoryColumnWidth(2200), 1460);
      expect(resolveSessionHistoryColumnWidth(double.infinity), 1460);
    });

    test('non-positive available resolves to zero', () {
      expect(resolveSessionHistoryColumnWidth(0), 0);
      expect(resolveSessionHistoryColumnWidth(-10), 0);
    });
  });
}

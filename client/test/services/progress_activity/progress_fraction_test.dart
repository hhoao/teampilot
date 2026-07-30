import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/progress_activity/progress_fraction.dart';

ProgressActivity _activity({
  double? fraction,
  int? completedItems,
  int? totalItems,
  int? bytesDone,
  int? bytesTotal,
}) {
  final now = DateTime(2026, 7, 30);
  return ProgressActivity(
    id: 'test-id',
    kind: ProgressActivityKind.fileTreeImport,
    title: 'Import',
    phase: ProgressActivityPhase.running,
    createdAt: now,
    updatedAt: now,
    fraction: fraction,
    completedItems: completedItems,
    totalItems: totalItems,
    bytesDone: bytesDone,
    bytesTotal: bytesTotal,
  );
}

void main() {
  group('resolveProgressFraction', () {
    test('uses explicit fraction when set', () {
      expect(
        resolveProgressFraction(_activity(fraction: 0.42)),
        0.42,
      );
    });

    test('explicit fraction wins over items and bytes', () {
      expect(
        resolveProgressFraction(
          _activity(
            fraction: 0.1,
            completedItems: 5,
            totalItems: 10,
            bytesDone: 100,
            bytesTotal: 200,
          ),
        ),
        0.1,
      );
    });

    test('uses zero fraction without falling through to items', () {
      expect(
        resolveProgressFraction(
          _activity(
            fraction: 0,
            completedItems: 5,
            totalItems: 10,
          ),
        ),
        0,
      );
    });

    test('derives fraction from completedItems and totalItems', () {
      expect(
        resolveProgressFraction(_activity(completedItems: 3, totalItems: 10)),
        0.3,
      );
    });

    test('treats null completedItems as zero when totalItems is positive', () {
      expect(
        resolveProgressFraction(_activity(totalItems: 4)),
        0,
      );
    });

    test('skips items when totalItems is zero', () {
      expect(
        resolveProgressFraction(
          _activity(
            completedItems: 1,
            totalItems: 0,
            bytesDone: 25,
            bytesTotal: 100,
          ),
        ),
        0.25,
      );
    });

    test('derives fraction from bytesDone and bytesTotal', () {
      expect(
        resolveProgressFraction(_activity(bytesDone: 50, bytesTotal: 200)),
        0.25,
      );
    });

    test('treats null bytesDone as zero when bytesTotal is positive', () {
      expect(
        resolveProgressFraction(_activity(bytesTotal: 100)),
        0,
      );
    });

    test('skips bytes when bytesTotal is zero', () {
      expect(resolveProgressFraction(_activity(bytesTotal: 0)), isNull);
    });

    test('returns null when no progress signal is available', () {
      expect(resolveProgressFraction(_activity()), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';

void main() {
  group('AiHistoryWatchMeta', () {
    test('reads changeWatchRoot and cacheTokenPaths from hints', () {
      final meta = AiHistoryWatchMeta.fromHints({
        'changeWatchRoot': '/proj',
        'cacheTokenPaths': '/proj/a.jsonl\n/proj/b.jsonl',
      });
      expect(meta?.changeWatchRoot, '/proj');
      expect(meta?.cacheTokenPaths, ['/proj/a.jsonl', '/proj/b.jsonl']);
    });

    test('returns null when root missing', () {
      expect(AiHistoryWatchMeta.fromHints({'cacheToken': 'x'}), isNull);
    });

    test('round-trips through toHints and fromHints', () {
      const original = AiHistoryWatchMeta(
        changeWatchRoot: '/proj',
        cacheTokenPaths: ['/proj/a.jsonl', '/proj/b.jsonl'],
      );
      final roundTripped = AiHistoryWatchMeta.fromHints(original.toHints());
      expect(roundTripped, isNotNull);
      expect(roundTripped!.changeWatchRoot, original.changeWatchRoot);
      expect(roundTripped.cacheTokenPaths, original.cacheTokenPaths);
    });
  });
}

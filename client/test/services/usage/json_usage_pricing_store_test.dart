import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage_pricing.dart';
import 'package:teampilot/services/usage/json_usage_pricing_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('round-trips user rules', () async {
    final fs = InMemoryFilesystem();
    final store = JsonUsagePricingStore(
      fs: fs,
      filePath: '/tp/usage/pricing.json',
    );
    const rule = UsagePriceRule(
      model: 'm',
      inputPerMillion: 1,
      outputPerMillion: 2,
      cacheReadPerMillion: 0.1,
      cacheWritePerMillion: 1.25,
      effectiveFromMs: 0,
    );

    await store.save([rule]);
    final loaded = await store.load();

    expect(loaded.corrupted, isFalse);
    expect(loaded.rules.single.model, 'm');
    expect(loaded.rules.single.inputPerMillion, 1);
  });

  test('corrupt file falls back to empty rules', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/tp/usage/pricing.json', '{bad');
    final store = JsonUsagePricingStore(
      fs: fs,
      filePath: '/tp/usage/pricing.json',
    );

    final loaded = await store.load();

    expect(loaded.corrupted, isTrue);
    expect(loaded.rules, isEmpty);
  });

  test('missing file is empty and not corrupt', () async {
    final store = JsonUsagePricingStore(
      fs: InMemoryFilesystem(),
      filePath: '/tp/usage/pricing.json',
    );

    final loaded = await store.load();

    expect(loaded.corrupted, isFalse);
    expect(loaded.rules, isEmpty);
  });
}

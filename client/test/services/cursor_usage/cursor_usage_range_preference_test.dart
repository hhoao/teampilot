import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_range_preference.dart';

import '../../support/in_memory_filesystem.dart';

const _path = '/tp/cursor_usage/range.json';

CursorUsageRangePreference _preference(InMemoryFilesystem fs) =>
    CursorUsageRangePreference(fs: fs, path: _path);

void main() {
  test('missing file loads the billing-cycle preset', () async {
    final range = await _preference(InMemoryFilesystem()).load();

    expect(range, const CursorUsagePresetRange(CursorUsagePreset.billingCycle));
  });

  test('saved custom range round-trips unchanged', () async {
    final fs = InMemoryFilesystem();
    final preference = _preference(fs);
    const custom = CursorUsageCustomRange(startMs: 1000, endMs: 2000);

    await preference.save(custom);

    expect(await preference.load(), custom);
  });

  test('corrupt file loads the default without throwing', () async {
    final fs = InMemoryFilesystem();
    fs.files[_path] = '{not json';

    final range = await _preference(fs).load();

    expect(range, const CursorUsagePresetRange(CursorUsagePreset.billingCycle));
  });
}

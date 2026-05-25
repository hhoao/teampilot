import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_lead_delegate_settings_merge.dart';

void main() {
  group('TeamLeadDelegateSettingsMerge', () {
    const hookCommand =
        'bash "/tmp/hooks/teampilot-team-lead-delegate-only.sh"';

    test('adds delegate-only PreToolUse hook', () {
      const merge = TeamLeadDelegateSettingsMerge();
      final out = merge.mergeIntoSettings(
        base: const {},
        hookCommand: hookCommand,
      );
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, hasLength(1));
      expect(
        (pre.first as Map)['matcher'],
        TeamLeadDelegateSettingsMerge.blockedToolsMatcher,
      );
    });

    test('stripFromSettings removes delegate hook', () {
      const merge = TeamLeadDelegateSettingsMerge();
      final withHook = merge.mergeIntoSettings(
        base: const {},
        hookCommand: hookCommand,
      );
      final stripped = merge.stripFromSettings(withHook);
      expect(stripped.containsKey('hooks'), isFalse);
    });

    test('is idempotent', () {
      const merge = TeamLeadDelegateSettingsMerge();
      final once = merge.mergeIntoSettings(
        base: const {},
        hookCommand: hookCommand,
      );
      final twice = merge.mergeIntoSettings(
        base: once,
        hookCommand: hookCommand,
      );
      expect(twice, once);
    });
  });
}

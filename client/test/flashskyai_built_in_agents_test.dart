import 'package:teampilot/constants/flashskyai_built_in_agents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activeDropdownValue maps empty, builtin, and custom', () {
    expect(
      FlashskyBuiltInAgents.activeDropdownValue(''),
      FlashskyBuiltInAgents.noneDropdownValue,
    );
    expect(
      FlashskyBuiltInAgents.activeDropdownValue('  '),
      FlashskyBuiltInAgents.noneDropdownValue,
    );
    expect(
      FlashskyBuiltInAgents.activeDropdownValue('general-purpose'),
      'general-purpose',
    );
    expect(
      FlashskyBuiltInAgents.activeDropdownValue(' my-agent '),
      FlashskyBuiltInAgents.customDropdownValue,
    );
  });

  test('dropdownValues starts with none and ends with custom', () {
    final v = FlashskyBuiltInAgents.dropdownValues();
    expect(v.first, FlashskyBuiltInAgents.noneDropdownValue);
    expect(v.last, FlashskyBuiltInAgents.customDropdownValue);
    expect(v, contains('flashskyai-code-guide'));
    expect(v, contains('statusline-setup'));
  });

  test('tryParseBuiltinId only matches known ids', () {
    expect(
      FlashskyBuiltInAgents.tryParseBuiltinId('general-purpose')!.id,
      'general-purpose',
    );
    expect(FlashskyBuiltInAgents.tryParseBuiltinId('unknown'), isNull);
  });
}

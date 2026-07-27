import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/services/selection_ai/selection_ai_menu_specs.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('builds disabled copy and Ask AI menu items', () {
    var copied = false;
    var asked = false;

    final specs = selectionAiMenuSpecs(
      l10n: l10n,
      enabled: false,
      onCopyAsAiContext: () => copied = true,
      onAskAi: () => asked = true,
    );

    expect(specs, hasLength(2));
    expect(specs[0].icon, Icons.auto_awesome_outlined);
    expect(specs[0].label, l10n.editorCopyAsAiContext);
    expect(specs[0].enabled, isFalse);
    expect(specs[1].icon, Icons.chat_outlined);
    expect(specs[1].label, l10n.selectionAskAi);
    expect(specs[1].enabled, isFalse);

    specs[0].onAction!();
    specs[1].onAction!();
    expect(copied, isTrue);
    expect(asked, isTrue);
  });
}

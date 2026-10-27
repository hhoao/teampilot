import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/chat/session_model_menu.dart';
import 'package:teampilot/services/acp/acp_session.dart';

void main() {
  const modelState = AcpModelState(
    configId: 'model',
    currentId: 'sonnet',
    options: [
      AcpModelOption(id: 'sonnet', name: 'Sonnet'),
      AcpModelOption(id: 'opus', name: 'Opus'),
    ],
  );

  test('puts live agent models first and nests launch config', () {
    final specs = buildSessionModelMenuSpecs(
      launchSpecs: const [
        TpActionMenuSpec.item(value: 'preset-x', label: 'Preset X'),
      ],
      modelState: modelState,
      agentSectionLabel: 'Agent model',
      launchSectionLabel: 'Launch config',
    );

    expect(specs, hasLength(5));
    expect(specs[0].enabled, isFalse);
    expect(specs[0].label, 'Agent model');
    expect(specs[1].value, const AcpModelPick('sonnet'));
    expect(specs[1].label, 'Sonnet');
    expect(specs[1].selected, isTrue);
    expect(specs[2].value, const AcpModelPick('opus'));
    expect(specs[2].selected, isFalse);
    expect(specs[3].isDivider, isTrue);
    expect(specs[4].isSubmenu, isTrue);
    expect(specs[4].label, 'Launch config');
    expect(specs[4].children, hasLength(1));
    expect(specs[4].children!.single.value, 'preset-x');
  });

  test('omits the launch submenu when there are no launch specs', () {
    final specs = buildSessionModelMenuSpecs(
      launchSpecs: const [],
      modelState: modelState,
      agentSectionLabel: 'Agent model',
      launchSectionLabel: 'Launch config',
    );

    expect(specs, hasLength(3));
    expect(specs.last.value, const AcpModelPick('opus'));
    expect(specs.where((spec) => spec.isDivider), isEmpty);
  });
}

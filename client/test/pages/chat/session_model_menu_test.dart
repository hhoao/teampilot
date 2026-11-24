import 'package:flutter/material.dart';
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

  test('agent rows show the configured context window in the subtitle', () {
    final specs = buildSessionModelMenuSpecs(
      launchSpecs: const [],
      modelState: modelState,
      agentSectionLabel: 'Agent model',
      launchSectionLabel: 'Launch config',
      modelContextWindowLabel: (id) => id == 'sonnet' ? '200K ctx' : null,
    );

    final sonnet = specs.firstWhere(
      (s) => s.value == const AcpModelPick('sonnet'),
    );
    expect((sonnet.subtitle as Text).data, '200K ctx');
    final opus = specs.firstWhere((s) => s.value == const AcpModelPick('opus'));
    expect(opus.subtitle, isNull);
  });

  test('agent subtitle keeps the description next to the context window', () {
    const withDescription = AcpModelState(
      configId: 'model',
      currentId: 'sonnet',
      options: [
        AcpModelOption(id: 'sonnet', name: 'Sonnet', description: 'Fast'),
      ],
    );
    final specs = buildSessionModelMenuSpecs(
      launchSpecs: const [],
      modelState: withDescription,
      agentSectionLabel: 'Agent model',
      launchSectionLabel: 'Launch config',
      modelContextWindowLabel: (_) => '300K ctx',
    );

    final row = specs.firstWhere(
      (s) => s.value == const AcpModelPick('sonnet'),
    );
    expect((row.subtitle as Text).data, 'Fast · 300K ctx');
  });

  group('acpModelIdForLaunch', () {
    test('uses the bare id when the agent advertises it', () {
      expect(
        acpModelIdForLaunch(state: modelState, namespace: '', model: 'sonnet'),
        'sonnet',
      );
    });

    test('qualifies the id with the picked namespace', () {
      const opencode = AcpModelState(
        configId: 'model',
        currentId: 'opencode/deepseek-v4.1-flash',
        options: [
          AcpModelOption(
            id: 'opencode-go/deepseek-v4.1-flash',
            name: 'Go Flash',
          ),
          AcpModelOption(id: 'opencode/deepseek-v4.1-flash', name: 'Zen Flash'),
        ],
      );

      expect(
        acpModelIdForLaunch(
          state: opencode,
          namespace: 'opencode-go',
          model: 'deepseek-v4.1-flash',
        ),
        'opencode-go/deepseek-v4.1-flash',
      );
      expect(
        acpModelIdForLaunch(
          state: opencode,
          namespace: 'opencode',
          model: 'deepseek-v4.1-flash',
        ),
        'opencode/deepseek-v4.1-flash',
      );
    });

    test('returns null when the agent does not advertise the pair', () {
      expect(
        acpModelIdForLaunch(
          state: modelState,
          namespace: 'opencode-go',
          model: 'my-custom-id',
        ),
        isNull,
      );
      expect(
        acpModelIdForLaunch(state: modelState, namespace: '', model: ''),
        isNull,
      );
    });
  });
}

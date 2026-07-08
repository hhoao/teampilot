import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest_store.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  const workspaceId = 'ws';
  const sessionId = 'sess';
  const tool = 'cursor';
  const slug = 'home-hhoa-git-hhoa-teampilot';

  late CliSessionManifestStore store;
  late CursorSessionLifecycleCapability capability;

  const busIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:9100/idle',
    sessionId: sessionId,
  );

  setUp(() {
    final fs = InMemoryFilesystem();
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    store = CliSessionManifestStore(fs: fs, layout: layout);
    capability = CursorSessionLifecycleCapability(manifestStore: store);
  });

  CliSessionManifestShared sharedPaths() => const CliSessionManifestShared(
    root: 'runtime/cursor',
    projectsDir: 'runtime/cursor/projects/$slug',
    cliConfigBase: 'runtime/cursor/cli-config.base.json',
  );

  Future<void> seedManifest({
    required CliSessionPhase phase,
    required Map<String, CliSessionManifestMember> members,
    Map<String, Map<String, CliSessionManifestSessionOverlay>>? sessionOverlays,
  }) {
    return store.write(
      workspaceId: workspaceId,
      tool: tool,
      manifest: CliSessionManifest(
        tool: tool,
        workspaceId: workspaceId,
        workspacePathHash: slug,
        workspaceSlug: slug,
        phase: phase,
        shared: sharedPaths(),
        members: members,
        sessionOverlays: sessionOverlays ?? const {},
      ),
    );
  }

  CliSessionManifestMember memberWithOverlay(int overlayGeneration) {
    return CliSessionManifestMember(
      homeRoot: 'runtime/team-lead/cursor/home',
    );
  }

  Map<String, Map<String, CliSessionManifestSessionOverlay>> overlaysFor(
    int overlayGeneration,
  ) {
    return {
      sessionId: {
        'team-lead': CliSessionManifestSessionOverlay(
          overlayGeneration: overlayGeneration,
        ),
        'architect': CliSessionManifestSessionOverlay(
          overlayGeneration: overlayGeneration,
        ),
      },
    };
  }

  CliSessionGateDecision gate({
    required String memberId,
    MemberBusIdleEndpoint? endpoint,
  }) {
    return capability.gateConnect(
      CliSessionGateContext(
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
        tool: CliTool.cursor,
        busIdle: endpoint ?? busIdle,
      ),
    );
  }

  group('CursorSessionLifecycleCapability.gateConnect', () {
    test('ready allows any member when overlay matches', () async {
      final overlayGen =
          CursorSessionLifecycleCapability.overlayGenerationForBus(busIdle);
      await seedManifest(
        phase: CliSessionPhase.ready,
        members: {
          'team-lead': memberWithOverlay(overlayGen),
          'architect': memberWithOverlay(overlayGen),
        },
        sessionOverlays: overlaysFor(overlayGen),
      );

      expect(gate(memberId: 'team-lead').allowed, isTrue);
      expect(gate(memberId: 'architect').allowed, isTrue);
    });

    test('degraded allows any member when overlay matches', () async {
      final overlayGen =
          CursorSessionLifecycleCapability.overlayGenerationForBus(busIdle);
      await seedManifest(
        phase: CliSessionPhase.degraded,
        members: {'team-lead': memberWithOverlay(overlayGen)},
        sessionOverlays: overlaysFor(overlayGen),
      );

      expect(gate(memberId: 'team-lead').allowed, isTrue);
    });

    test('ready denies when overlay generation is stale', () async {
      final overlayGen =
          CursorSessionLifecycleCapability.overlayGenerationForBus(busIdle);
      await seedManifest(
        phase: CliSessionPhase.ready,
        members: {'team-lead': memberWithOverlay(overlayGen + 1)},
        sessionOverlays: {
          sessionId: {
            'team-lead': CliSessionManifestSessionOverlay(
              overlayGeneration: overlayGen + 1,
            ),
          },
        },
      );

      final decision = gate(memberId: 'team-lead');
      expect(decision.allowed, isFalse);
      expect(decision.reason, 'overlay');
    });

    test('denies when manifest is missing', () {
      final decision = gate(memberId: 'team-lead');
      expect(decision.allowed, isFalse);
      expect(decision.reason, 'manifest');
    });
  });
}

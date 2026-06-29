import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/theme/workspace_topology_colors.dart';

void main() {
  test('remote and mixed base accents differ by brightness', () {
    expect(
      WorkspaceTopologyColors.remote(Brightness.light),
      const Color(0xFF4A8B57),
    );
    expect(
      WorkspaceTopologyColors.mixed(Brightness.dark),
      const Color(0xFFC9A85A),
    );
  });

  test('of maps local to primary and tones remote toward surface', () {
    final scheme = ThemeData.light().colorScheme;
    expect(
      WorkspaceTopologyColors.of(
        topology: WorkspaceTopology.local,
        colorScheme: scheme,
        brightness: Brightness.light,
      ),
      scheme.primary,
    );
    final remote = WorkspaceTopologyColors.of(
      topology: WorkspaceTopology.remote,
      colorScheme: scheme,
      brightness: Brightness.light,
    );
    final raw = WorkspaceTopologyColors.remote(Brightness.light);
    expect(remote, isNot(raw));
    expect(
      remote,
      WorkspaceTopologyColors.toneForTest(accent: raw, colorScheme: scheme),
    );
    expect(remote.computeLuminance(), lessThan(raw.computeLuminance()));
  });
}

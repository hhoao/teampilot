import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/theme/workspace_topology_colors.dart';

void main() {
  late ColorScheme cs;

  setUp(() {
    cs = const ColorScheme.light(
      primary: Color(0xFF0066CC),
      tertiary: Color(0xFFCC6600),
    );
  });

  test('local tab bar uses primary topology color when active', () {
    final color = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: Brightness.light,
      active: true,
      hovered: false,
    );
    expect(color, cs.primary);
  });

  test('team and personal local tabs share the same topology bar color', () {
    final personal = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: Brightness.light,
      topology: WorkspaceTopology.local,
      active: true,
      hovered: false,
    );
    final teamBar = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: Brightness.light,
      topology: WorkspaceTopology.local,
      active: true,
      hovered: false,
    );
    expect(personal, teamBar);
    expect(personal, cs.primary);
  });

  test('kind icons match home sidebar semantics', () {
    expect(
      homeWorkspaceTabKindIcon(HomeWorkspaceTabKind.personal),
      Icons.person_outline_rounded,
    );
    expect(
      homeWorkspaceTabKindIcon(HomeWorkspaceTabKind.team),
      Icons.groups_2_outlined,
    );
  });

  test('inactive tab bar alpha is lower than active', () {
    final inactive = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: Brightness.light,
      active: false,
      hovered: false,
    );
    final active = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: Brightness.light,
      active: true,
      hovered: false,
    );
    expect(inactive.a, lessThan(active.a));
    expect(inactive.a, closeTo(0.4, 0.01));
  });

  test('inactive hovered tab bar alpha is between inactive and active', () {
    final hovered = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: Brightness.light,
      active: false,
      hovered: true,
    );
    final inactive = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: Brightness.light,
      active: false,
      hovered: false,
    );
    expect(hovered.a, greaterThan(inactive.a));
    expect(hovered.a, closeTo(0.7, 0.01));
  });

  test('workspaceTabTopologyIconColor uses toned remote for remote', () {
    final base = WorkspaceTopologyColors.of(
      topology: WorkspaceTopology.remote,
      colorScheme: cs,
      brightness: Brightness.light,
    );
    final color = workspaceTabTopologyIconColor(
      colorScheme: cs,
      brightness: Brightness.light,
      topology: WorkspaceTopology.remote,
    );
    expect(color, base.withValues(alpha: 0.8));
  });

  test('workspaceTabTopologyIconColor uses toned mixed for mixed', () {
    final base = WorkspaceTopologyColors.of(
      topology: WorkspaceTopology.mixed,
      colorScheme: cs,
      brightness: Brightness.dark,
    );
    final color = workspaceTabTopologyIconColor(
      colorScheme: cs,
      brightness: Brightness.dark,
      topology: WorkspaceTopology.mixed,
      active: true,
    );
    expect(color, base.withValues(alpha: 1));
  });
}

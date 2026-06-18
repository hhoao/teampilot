import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';

void main() {
  late ColorScheme cs;

  setUp(() {
    cs = const ColorScheme.light(
      primary: Color(0xFF0066CC),
      tertiary: Color(0xFFCC6600),
    );
  });

  test('personal tab uses primary at full alpha when active', () {
    final color = homeProjectTabBarColor(
      kind: HomeWorkspaceTabKind.personal,
      colorScheme: cs,
      active: true,
      hovered: false,
    );
    expect(color, cs.primary);
  });

  test('team tab uses complement of primary at full alpha when active', () {
    final color = homeProjectTabBarColor(
      kind: HomeWorkspaceTabKind.team,
      colorScheme: cs,
      active: true,
      hovered: false,
    );
    expect(color, homeProjectTabComplementColor(cs.primary));
  });

  test('kind icons match home sidebar semantics', () {
    expect(
      homeProjectTabKindIcon(HomeWorkspaceTabKind.personal),
      Icons.person_outline_rounded,
    );
    expect(
      homeProjectTabKindIcon(HomeWorkspaceTabKind.team),
      Icons.groups_2_outlined,
    );
  });

  test('inactive tab bar alpha is lower than active', () {
    final inactive = homeProjectTabBarColor(
      kind: HomeWorkspaceTabKind.personal,
      colorScheme: cs,
      active: false,
      hovered: false,
    );
    final active = homeProjectTabBarColor(
      kind: HomeWorkspaceTabKind.personal,
      colorScheme: cs,
      active: true,
      hovered: false,
    );
    expect(inactive.a, lessThan(active.a));
    expect(inactive.a, closeTo(0.4, 0.01));
  });

  test('inactive hovered tab bar alpha is between inactive and active', () {
    final hovered = homeProjectTabBarColor(
      kind: HomeWorkspaceTabKind.team,
      colorScheme: cs,
      active: false,
      hovered: true,
    );
    final inactive = homeProjectTabBarColor(
      kind: HomeWorkspaceTabKind.team,
      colorScheme: cs,
      active: false,
      hovered: false,
    );
    expect(hovered.a, greaterThan(inactive.a));
    expect(hovered.a, closeTo(0.7, 0.01));
  });
}

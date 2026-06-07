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
      kind: HomeProjectTabKind.personal,
      colorScheme: cs,
      active: true,
      hovered: false,
    );
    expect(color, cs.primary);
  });

  test('team tab uses tertiary at full alpha when active', () {
    final color = homeProjectTabBarColor(
      kind: HomeProjectTabKind.team,
      colorScheme: cs,
      active: true,
      hovered: false,
    );
    expect(color, cs.tertiary);
  });

  test('inactive tab bar alpha is lower than active', () {
    final inactive = homeProjectTabBarColor(
      kind: HomeProjectTabKind.personal,
      colorScheme: cs,
      active: false,
      hovered: false,
    );
    final active = homeProjectTabBarColor(
      kind: HomeProjectTabKind.personal,
      colorScheme: cs,
      active: true,
      hovered: false,
    );
    expect(inactive.a, lessThan(active.a));
    expect(inactive.a, closeTo(0.4, 0.01));
  });

  test('inactive hovered tab bar alpha is between inactive and active', () {
    final hovered = homeProjectTabBarColor(
      kind: HomeProjectTabKind.team,
      colorScheme: cs,
      active: false,
      hovered: true,
    );
    final inactive = homeProjectTabBarColor(
      kind: HomeProjectTabKind.team,
      colorScheme: cs,
      active: false,
      hovered: false,
    );
    expect(hovered.a, greaterThan(inactive.a));
    expect(hovered.a, closeTo(0.7, 0.01));
  });
}

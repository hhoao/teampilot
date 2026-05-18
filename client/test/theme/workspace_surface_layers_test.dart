import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

void main() {
  test('workspace surfaces map to stable Material surface levels', () {
    const scheme = ColorScheme.light(
      primary: Color(0xFF111111),
      onPrimary: Color(0xFFFFFFFF),
      secondary: Color(0xFF222222),
      onSecondary: Color(0xFFFFFFFF),
      error: Color(0xFF333333),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFFAFAFA),
      onSurface: Color(0xFF101010),
      surfaceContainerLow: Color(0xFFF3F4F6),
      surfaceContainer: Color(0xFFE5E7EB),
      surfaceContainerHigh: Color(0xFFD1D5DB),
      surfaceContainerHighest: Color(0xFF9CA3AF),
    );

    expect(scheme.workspacePage, scheme.surface);
    expect(scheme.workspaceSubtleSurface, scheme.surfaceContainerLow);
    expect(scheme.workspaceCard, scheme.surfaceContainer);
    expect(scheme.workspaceInset, scheme.surfaceContainerHigh);
    expect(scheme.workspaceCode, scheme.surfaceContainerHighest);
  });
}

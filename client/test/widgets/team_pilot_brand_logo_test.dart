import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/team_pilot_brand_logo.dart';

void main() {
  testWidgets(
    'default logo size follows icon theme (ignores text-size preset)',
    (tester) async {
      Future<double> defaultLogoWidth(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(theme.iconTheme.size),
            theme: theme,
            home: const Scaffold(body: TeamPilotBrandLogo()),
          ),
        );
        final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
        return svg.width!;
      }

      final std = buildDarkTheme(null, AppTypographyScale.standard);
      final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

      final stdWidth = await defaultLogoWidth(std);
      final comfyWidth = await defaultLogoWidth(comfy);

      expect(stdWidth, std.iconTheme.size);
      // IconTheme tracks OS text baseline only; in-app text-size presets
      // do not change toolbar / brand icon sizes at the same baseline.
      expect(comfyWidth, stdWidth);
      expect(comfyWidth, comfy.iconTheme.size);
    },
  );
}

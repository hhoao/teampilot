import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../services/app/platform_utils.dart';
import '../widgets/desktop_window_title_bar.dart';

/// TeamPilot toast overlay defaults for [TpToastWrapper].
TpToastConfig buildTeamPilotToastConfig() {
  return TpToastConfig(
    alignment: AlignmentDirectional.topEnd,
    itemWidth: 400,
    maxToastLimit: 1,
    animationDuration: const Duration(milliseconds: 200),
    maxTitleLines: 3,
    maxDescriptionLines: 1,
    marginBuilder: (context, alignment) {
      final spacing = context.tpSpacing;
      final horizontal = spacing.lg;
      final y = alignment.resolve(Directionality.of(context)).y;
      if (y <= -0.5) {
        var top = spacing.lg + MediaQuery.viewPaddingOf(context).top;
        if (useCustomDesktopWindowTitleBar) {
          top += kDesktopWindowTitleBarHeight;
        }
        return EdgeInsets.only(left: horizontal, right: horizontal, top: top);
      }
      final bottom = spacing.lg + MediaQuery.viewPaddingOf(context).bottom;
      return EdgeInsets.only(
        left: horizontal,
        right: horizontal,
        bottom: bottom,
      );
    },
  );
}

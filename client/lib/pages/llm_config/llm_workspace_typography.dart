import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

/// 本页排版：沿用 [ThemeData.textTheme]，仅「小 / 中 / 面板标题」三档字号来源；
/// 字重只在 regular、[FontWeight.w500]、[FontWeight.w600] 之间选（不出现 w700/w800）。
class LlmWorkspaceText {
  const LlmWorkspaceText(this.theme);

  final ThemeData theme;

  AppTextStyles get _tx => AppTextStyles(theme);

  /// 小：徽章、次要说明、紧凑链接。
  TextStyle get small => _tx.caption;

  TextStyle smallColored(Color color, {FontWeight? fontWeight}) =>
      _tx.captionColored(color, fontWeight: fontWeight);

  /// 中：正文、只读值。
  TextStyle get body => _tx.body;

  TextStyle bodyColored(Color color) => _tx.bodyColored(color);

  /// 中强调：行标题、列表主名称。
  TextStyle get bodyStrong => _tx.bodyStrong;

  TextStyle bodyStrongColored(Color color) => _tx.bodyStrongColored(color);

  /// 面板顶栏标题（不做更大字号档位）。
  TextStyle get panelHeader => _tx.sectionTitle;

  TextStyle panelHeaderColored(Color color) => _tx.sectionTitleColored(color);

  TextStyle get mutedBody => _tx.mutedBody;

  TextStyle get mutedSmall => _tx.mutedCaption;
}

/// Provider detail pane: typography and [ColorScheme] from app [ThemeData].
class LlmProviderDetailLook {
  const LlmProviderDetailLook._(this.theme);

  factory LlmProviderDetailLook.of(BuildContext context) {
    return LlmProviderDetailLook._(Theme.of(context));
  }

  final ThemeData theme;

  LlmWorkspaceText get _tx => LlmWorkspaceText(theme);

  ColorScheme get colorScheme => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;

  Color get panelBg => colorScheme.workspaceCard;

  Color get borderColor => colorScheme.outlineVariant;

  Color get insetPanelBg => colorScheme.workspaceInset;

  Color get insetPanelBorder => colorScheme.outlineVariant;

  TextStyle get panelTitleStyle =>
      _tx.panelHeaderColored(colorScheme.onSurface);

  TextStyle get mutedBodyStyle => _tx.mutedSmall;

  TextStyle get rowLabelStyle =>
      _tx.bodyStrongColored(colorScheme.onSurface).copyWith(height: 1.2);

  TextStyle get sectionTitleStyle =>
      _tx.panelHeaderColored(colorScheme.onSurface);

  /// 只读字段内文字：中档 + 弱化色。
  TextStyle get valueBoxStyle => _tx.mutedBody;
}

class LlmSettingRow extends StatelessWidget {
  const LlmSettingRow({super.key, required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final look = LlmProviderDetailLook.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final labelW = (c.maxWidth * 0.30).clamp(104.0, 152.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelW,
                child: Text(
                  title,
                  style: look.rowLabelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LlmSettingFieldBlock extends StatelessWidget {
  const LlmSettingFieldBlock({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = LlmProviderDetailLook.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: look.rowLabelStyle),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

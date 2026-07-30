import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_typography_scale.dart';

/// Typography scale preset strip; shows a percent field when [scaleId] is `custom`.
class TypographyScaleSetting extends StatefulWidget {
  const TypographyScaleSetting({
    required this.scaleId,
    required this.customMultiplier,
    required this.onScaleIdChanged,
    required this.onCustomMultiplierChanged,
    super.key,
  });

  final String scaleId;
  final double customMultiplier;
  final ValueChanged<String> onScaleIdChanged;
  final ValueChanged<double> onCustomMultiplierChanged;

  @override
  State<TypographyScaleSetting> createState() => _TypographyScaleSettingState();
}

class _TypographyScaleSettingState extends State<TypographyScaleSetting> {
  late final TextEditingController _percentController;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(
      text: _percentText(widget.customMultiplier),
    );
  }

  @override
  void didUpdateWidget(covariant TypographyScaleSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customMultiplier != widget.customMultiplier) {
      final next = _percentText(widget.customMultiplier);
      if (_percentController.text != next) {
        _percentController.text = next;
      }
    }
  }

  @override
  void dispose() {
    _percentController.dispose();
    super.dispose();
  }

  static String _percentText(double multiplier) =>
      (multiplier * 100).round().toString();

  void _commitPercentInput() {
    final parsed = int.tryParse(_percentController.text.trim());
    if (parsed == null) {
      _percentController.text = _percentText(widget.customMultiplier);
      return;
    }
    final multiplier = clampTypographyCustomMultiplier(parsed / 100);
    _percentController.text = _percentText(multiplier);
    widget.onCustomMultiplierChanged(multiplier);
  }

  List<TpSegmentedOption<String>> _segments(AppLocalizations l10n) => [
    TpSegmentedOption<String>(
      value: 'compact',
      label: l10n.typographyScaleCompact,
      icon: Icons.density_small_outlined,
    ),
    TpSegmentedOption<String>(
      value: 'standard',
      label: l10n.typographyScaleStandard,
      icon: Icons.density_medium_outlined,
    ),
    TpSegmentedOption<String>(
      value: 'comfortable',
      label: l10n.typographyScaleComfortable,
      icon: Icons.density_large_outlined,
    ),
    TpSegmentedOption<String>(
      value: 'custom',
      label: l10n.typographyScaleCustom,
      icon: Icons.tune_outlined,
    ),
  ];

  void _onScaleChanged(String id) {
    widget.onScaleIdChanged(id);
    if (id == 'custom') {
      widget.onCustomMultiplierChanged(widget.customMultiplier);
    }
  }

  Widget _percentField(AppLocalizations l10n) {
    return SizedBox(
      width: 96,
      height: tpSegmentedControlMinHeight,
      child: TextField(
        controller: _percentController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.typographyScaleCustomHint,
          suffixText: '%',
        ),
        onSubmitted: (_) => _commitPercentInput(),
        onEditingComplete: _commitPercentInput,
        onTapOutside: (_) => _commitPercentInput(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isCustom = widget.scaleId == 'custom';
    final narrow =
        MediaQuery.sizeOf(context).width < kTpSegmentedPickerMobileBreakpoint;

    // Mobile select: fill trailing width so the chevron sits on the far right.
    // Do not wrap in an unbounded horizontal ScrollView (that pins the arrow
    // next to the label).
    if (narrow) {
      return Row(
        children: [
          Expanded(
            child: TpSegmentedPicker<String>(
              segments: _segments(l10n),
              selected: widget.scaleId,
              onChanged: _onScaleChanged,
            ),
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            _percentField(l10n),
          ],
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TpSegmentedPicker<String>(
              alignment: Alignment.centerRight,
              scrollable: false,
              segments: _segments(l10n),
              selected: widget.scaleId,
              onChanged: _onScaleChanged,
            ),
            if (isCustom) ...[
              const SizedBox(width: 8),
              _percentField(l10n),
            ],
          ],
        ),
      ),
    );
  }
}

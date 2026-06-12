import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_typography_scale.dart';

/// Whole-UI zoom control: a percent field clamped to [kUiZoomMin]–[kUiZoomMax].
///
/// Independent of [TypographyScaleSetting] (which is text size); this drives the
/// root [UiZoom] so the entire interface scales together.
class UiZoomSetting extends StatefulWidget {
  const UiZoomSetting({
    required this.zoom,
    required this.onChanged,
    super.key,
  });

  final double zoom;
  final ValueChanged<double> onChanged;

  @override
  State<UiZoomSetting> createState() => _UiZoomSettingState();
}

class _UiZoomSettingState extends State<UiZoomSetting> {
  late final TextEditingController _percentController;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(text: _percentText(widget.zoom));
  }

  @override
  void didUpdateWidget(covariant UiZoomSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom != widget.zoom) {
      final next = _percentText(widget.zoom);
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

  static String _percentText(double zoom) => (zoom * 100).round().toString();

  void _commit() {
    final parsed = int.tryParse(_percentController.text.trim());
    if (parsed == null) {
      _percentController.text = _percentText(widget.zoom);
      return;
    }
    final zoom = clampUiZoom(parsed / 100);
    _percentController.text = _percentText(zoom);
    widget.onChanged(zoom);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: 96,
      height: 38,
      child: TextField(
        controller: _percentController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.uiZoomHint,
          suffixText: '%',
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        onTapOutside: (_) => _commit(),
      ),
    );
  }
}

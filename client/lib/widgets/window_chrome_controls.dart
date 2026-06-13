import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../l10n/l10n_extensions.dart';
import '../services/app/platform_utils.dart';

/// Default height for [WindowChromeControls] when embedded in
/// [DesktopWindowTitleBar].
const double kDefaultWindowChromeHeight = 40;

/// Desktop window controls: macOS traffic lights (left) or Windows-style icons.
class WindowChromeControls extends StatelessWidget {
  const WindowChromeControls({
    required this.isMaximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    this.height = kDefaultWindowChromeHeight,
    super.key,
  });

  final bool isMaximized;
  final Future<void> Function() onMinimize;
  final Future<void> Function() onToggleMaximize;
  final Future<void> Function() onClose;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!useCustomDesktopWindowTitleBar) {
      return const SizedBox.shrink();
    }

    if (useMacWindowChromeStyle) {
      return MacTrafficLightControls(
        isMaximized: isMaximized,
        height: height,
        onMinimize: onMinimize,
        onToggleMaximize: onToggleMaximize,
        onClose: onClose,
      );
    }

    return WindowsStyleChromeControls(
      isMaximized: isMaximized,
      height: height,
      onMinimize: onMinimize,
      onToggleMaximize: onToggleMaximize,
      onClose: onClose,
    );
  }
}

/// macOS close / minimize / maximize traffic-light cluster.
class MacTrafficLightControls extends StatefulWidget {
  const MacTrafficLightControls({
    required this.isMaximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    this.height = kDefaultWindowChromeHeight,
    super.key,
  });

  final bool isMaximized;
  final Future<void> Function() onMinimize;
  final Future<void> Function() onToggleMaximize;
  final Future<void> Function() onClose;
  final double height;

  @override
  State<MacTrafficLightControls> createState() =>
      _MacTrafficLightControlsState();
}

class _MacTrafficLightControlsState extends State<MacTrafficLightControls> {
  bool _hovered = false;

  static const _closeColor = Color(0xFFFF5F57);
  static const _minimizeColor = Color(0xFFFEBC2E);
  static const _maximizeColor = Color(0xFF28C840);
  static const _symbolColor = Color(0xFF3E3E3E);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: widget.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TrafficLightButton(
                color: _closeColor,
                tooltip: l10n.windowControlClose,
                symbol: '×',
                showSymbol: _hovered,
                onPressed: widget.onClose,
              ),
              const SizedBox(width: 8),
              _TrafficLightButton(
                color: _minimizeColor,
                tooltip: l10n.windowControlMinimize,
                symbol: '−',
                showSymbol: _hovered,
                onPressed: widget.onMinimize,
              ),
              const SizedBox(width: 8),
              _TrafficLightButton(
                color: _maximizeColor,
                tooltip: widget.isMaximized
                    ? l10n.windowControlRestore
                    : l10n.windowControlMaximize,
                showSymbol: _hovered,
                onPressed: widget.onToggleMaximize,
                child: widget.isMaximized
                    ? const _TrafficLightRestoreGlyph()
                    : Text(
                        '+',
                        style: _trafficLightSymbolStyle(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrafficLightRestoreGlyph extends StatelessWidget {
  const _TrafficLightRestoreGlyph();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(8, 8),
      painter: _RestoreGlyphPainter(),
    );
  }
}

class _RestoreGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _MacTrafficLightControlsState._symbolColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const inset = 0.5;
    final w = size.width;
    final h = size.height;
    final halfW = w * 0.42;
    final halfH = h * 0.42;

    canvas.drawRect(
      Rect.fromLTWH(inset, inset + 1.5, halfW, halfH),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(inset + 2.5, inset, halfW, halfH),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

TextStyle _trafficLightSymbolStyle() {
  return const TextStyle(
    fontSize: 11,
    height: 1,
    fontWeight: FontWeight.w700,
    color: _MacTrafficLightControlsState._symbolColor,
  );
}

class _TrafficLightButton extends StatelessWidget {
  const _TrafficLightButton({
    required this.color,
    required this.tooltip,
    required this.showSymbol,
    required this.onPressed,
    this.symbol,
    this.child,
  });

  static const double diameter = 12;

  final Color color;
  final String tooltip;
  final bool showSymbol;
  final Future<void> Function() onPressed;
  final String? symbol;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => onPressed(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.14),
              width: 0.5,
            ),
          ),
          child: showSymbol
              ? (child ??
                    Text(
                      symbol!,
                      style: _trafficLightSymbolStyle(),
                    ))
              : null,
        ),
      ),
    );
  }
}

/// Windows / Linux minimize, maximize, and close buttons.
class WindowsStyleChromeControls extends StatelessWidget {
  const WindowsStyleChromeControls({
    required this.isMaximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    this.height = kDefaultWindowChromeHeight,
    super.key,
  });

  final bool isMaximized;
  final Future<void> Function() onMinimize;
  final Future<void> Function() onToggleMaximize;
  final Future<void> Function() onClose;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowsChromeButton(
          height: height,
          tooltip: l10n.windowControlMinimize,
          icon: Icons.remove,
          onPressed: onMinimize,
        ),
        _WindowsChromeButton(
          height: height,
          tooltip: isMaximized
              ? l10n.windowControlRestore
              : l10n.windowControlMaximize,
          icon: isMaximized ? Icons.filter_none : Icons.crop_square_outlined,
          onPressed: onToggleMaximize,
        ),
        _WindowsChromeButton(
          height: height,
          tooltip: l10n.windowControlClose,
          icon: Icons.close,
          isClose: true,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _WindowsChromeButton extends StatefulWidget {
  const _WindowsChromeButton({
    required this.height,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final double height;
  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool isClose;

  @override
  State<_WindowsChromeButton> createState() => _WindowsChromeButtonState();
}

class _WindowsChromeButtonState extends State<_WindowsChromeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color background = Colors.transparent;
    Color foreground = isDark
        ? Colors.white.withValues(alpha: 0.88)
        : const Color(0xFF374151);

    if (_hovered) {
      if (widget.isClose) {
        background = const Color(0xFFE81123);
        foreground = Colors.white;
      } else {
        background = isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06);
      }
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          width: 46,
          height: widget.height,
          child: Material(
            color: background,
            child: InkWell(
              onTap: () => widget.onPressed(),
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Icon(
                widget.icon,
                size: context.appIconSizes.md,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

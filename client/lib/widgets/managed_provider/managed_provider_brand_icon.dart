import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/managed_provider.dart';
import '../app_provider/provider_brand_icon.dart';
import '../app_provider/provider_icon_registry.dart';

sealed class ManagedProviderBrandIconSpec {
  const ManagedProviderBrandIconSpec();
  const factory ManagedProviderBrandIconSpec.bundled(String key) =
      ManagedProviderBundledIcon;
  const factory ManagedProviderBrandIconSpec.remote(String url) =
      ManagedProviderRemoteIcon;
  const factory ManagedProviderBrandIconSpec.initials(String name) =
      ManagedProviderInitialsIcon;
}

class ManagedProviderBundledIcon extends ManagedProviderBrandIconSpec {
  const ManagedProviderBundledIcon(this.key);
  final String key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedProviderBundledIcon && key == other.key;

  @override
  int get hashCode => key.hashCode;
}

class ManagedProviderRemoteIcon extends ManagedProviderBrandIconSpec {
  const ManagedProviderRemoteIcon(this.url);
  final String url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedProviderRemoteIcon && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

class ManagedProviderInitialsIcon extends ManagedProviderBrandIconSpec {
  const ManagedProviderInitialsIcon(this.name);
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedProviderInitialsIcon && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

ManagedProviderBrandIconSpec resolveManagedProviderBrandIcon(
  ManagedProvider provider,
) {
  final adapter = provider.adapterId.trim();
  if (adapter == 'official-codex-subscription') {
    return const ManagedProviderBrandIconSpec.bundled('openai');
  }
  if (adapter == 'official-claude-subscription') {
    return const ManagedProviderBrandIconSpec.bundled('claude');
  }
  final host = Uri.tryParse(provider.endpointConfig.url)?.host.toLowerCase();
  if (adapter == 'http-json' &&
      (host == 'api.deepseek.com' ||
          provider.name.trim().toLowerCase() == 'deepseek')) {
    return const ManagedProviderBrandIconSpec.bundled('deepseek');
  }
  final iconUrl = provider.brand.iconUrl?.trim() ?? '';
  if (iconUrl.startsWith('https://')) {
    return ManagedProviderBrandIconSpec.remote(iconUrl);
  }
  return ManagedProviderBrandIconSpec.initials(provider.name);
}

const managedProviderBrandLabelTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

double managedProviderBrandLabelLineHeight(
  TextStyle style,
  TextScaler scaler,
) {
  final fontSize = scaler.scale(style.fontSize ?? 12);
  return fontSize * (style.height ?? 1.2);
}

/// Vertically centers a brand mark with adjacent label text.
class ManagedProviderBrandLabelRow extends StatelessWidget {
  const ManagedProviderBrandLabelRow({
    required this.leading,
    required this.label,
    required this.iconSize,
    required this.textStyle,
    this.spacing = 7,
    this.expanded = false,
    this.between = const [],
    super.key,
  });

  final Widget leading;
  final String? label;
  final double iconSize;
  final TextStyle textStyle;
  final double spacing;
  final bool expanded;
  final List<Widget> between;

  @override
  Widget build(BuildContext context) {
    final trimmed = label?.trim();
    final hasLabel = trimmed != null && trimmed.isNotEmpty;
    final scaler = MediaQuery.textScalerOf(context);
    final resolvedStyle = textStyle;
    final rowHeight = hasLabel
        ? math.max(iconSize, managedProviderBrandLabelLineHeight(resolvedStyle, scaler))
        : iconSize;

    final children = <Widget>[
      SizedBox(
        width: iconSize,
        height: iconSize,
        child: Center(child: leading),
      ),
      ...between,
    ];

    if (hasLabel) {
      children.add(SizedBox(width: spacing));
      final labelWidget = Text(
        trimmed,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: resolvedStyle,
        textHeightBehavior: managedProviderBrandLabelTextHeightBehavior,
      );
      children.add(expanded ? Expanded(child: labelWidget) : labelWidget);
    }

    return SizedBox(
      height: rowHeight,
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}

class ManagedProviderBrandMark extends StatelessWidget {
  const ManagedProviderBrandMark({
    required this.provider,
    this.size = 20,
    this.showBorder = false,
    super.key,
  });

  final ManagedProvider provider;
  final double size;
  final bool showBorder;

  static const _borderRadius = 4.0;

  @override
  Widget build(BuildContext context) {
    final spec = resolveManagedProviderBrandIcon(provider);
    return switch (spec) {
      ManagedProviderBundledIcon(:final key) => ProviderBrandIcon(
        icon: key,
        name: provider.name,
        size: size,
        borderRadius: _borderRadius,
        showBorder: showBorder,
      ),
      ManagedProviderRemoteIcon(:final url) => _RemoteBrandIcon(
        url: url,
        name: provider.name,
        size: size,
        showBorder: showBorder,
      ),
      ManagedProviderInitialsIcon() => ProviderBrandIcon(
        icon: '',
        name: provider.name,
        size: size,
        borderRadius: _borderRadius,
        showBorder: showBorder,
      ),
    };
  }
}

class _RemoteBrandIcon extends StatelessWidget {
  const _RemoteBrandIcon({
    required this.url,
    required this.name,
    required this.size,
    required this.showBorder,
  });

  final String url;
  final String name;
  final double size;
  final bool showBorder;

  BoxDecoration _tileDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: resolveProviderIconTileBackground(cs, isDark),
      borderRadius: BorderRadius.circular(ManagedProviderBrandMark._borderRadius),
      border: showBorder
          ? Border.all(color: resolveProviderIconBorderColor(cs, isDark))
          : null,
    );
  }

  Widget _successTile(BuildContext context, Widget image) {
    return Container(
      width: size,
      height: size,
      decoration: _tileDecoration(context),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => ProviderBrandIcon(
        icon: '',
        name: name,
        size: size,
        borderRadius: ManagedProviderBrandMark._borderRadius,
        showBorder: showBorder,
      ),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) {
          return Container(
            width: size,
            height: size,
            decoration: _tileDecoration(context),
            clipBehavior: Clip.antiAlias,
          );
        }
        return _successTile(context, child);
      },
    );
  }
}

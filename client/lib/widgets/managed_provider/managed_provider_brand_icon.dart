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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = resolveProviderIconTileBackground(cs, isDark);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(ManagedProviderBrandMark._borderRadius),
        border: showBorder
            ? Border.all(color: resolveProviderIconBorderColor(cs, isDark))
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => ProviderBrandIcon(
            icon: '',
            name: name,
            size: size,
            borderRadius: ManagedProviderBrandMark._borderRadius,
            showBorder: showBorder,
          ),
        ),
      ),
    );
  }
}

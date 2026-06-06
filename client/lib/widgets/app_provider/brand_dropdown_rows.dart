import 'package:flutter/material.dart';
import 'package:teampilot/models/app_provider_config.dart';

import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../cli/cli_brand_icon.dart';
import 'provider_brand_icon.dart';

const double kBrandDropdownIconSize = 20;

/// Icon + label row for dropdown headers and list items.
class BrandDropdownRow extends StatelessWidget {
  const BrandDropdownRow({
    required this.label,
    required this.leading,
    this.iconSize = kBrandDropdownIconSize,
    this.style,
    super.key,
  });

  final String label;
  final Widget leading;
  final double iconSize;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: iconSize, height: iconSize, child: leading),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

Widget cliDropdownRow(
  BuildContext context, {
  required CliTool cli,
  required String label,
  CliToolRegistry? registry,
  TextStyle? style,
}) {
  final definition = registry?.tryGet(cli);
  return BrandDropdownRow(
    label: label,
    style: style,
    leading: CliBrandIcon(
      cli: cli,
      definition: definition,
      label: label,
      size: kBrandDropdownIconSize,
      borderRadius: 5,
      showBorder: false,
    ),
  );
}

Widget providerDropdownRow(
  BuildContext context, {
  required String label,
  AppProviderConfig? provider,
  TextStyle? style,
}) {
  final leading = provider != null
      ? ProviderBrandIcon.fromConfig(
          provider,
          size: kBrandDropdownIconSize,
          borderRadius: 5,
          showBorder: false,
        )
      : ProviderBrandIcon(
          icon: '',
          name: label,
          size: kBrandDropdownIconSize,
          borderRadius: 5,
          showBorder: false,
        );
  return BrandDropdownRow(label: label, style: style, leading: leading);
}

Widget Function(BuildContext context, CliTool cli) cliDropdownItemBuilder({
  required CliToolRegistry? registry,
  required dynamic l10n,
}) {
  return (context, cli) {
    final def = registry?.tryGet(cli);
    final label = def == null ? cli.value : cliDisplayName(def, l10n);
    return cliDropdownRow(context, cli: cli, label: label, registry: registry);
  };
}

Widget Function(BuildContext context, String providerId)
providerDropdownItemBuilder({
  required Iterable<AppProviderConfig> providers,
  required String Function(String id) labelFor,
}) {
  return (context, providerId) {
    AppProviderConfig? provider;
    for (final candidate in providers) {
      if (candidate.id == providerId) {
        provider = candidate;
        break;
      }
    }
    return providerDropdownRow(
      context,
      label: labelFor(providerId),
      provider: provider,
    );
  };
}

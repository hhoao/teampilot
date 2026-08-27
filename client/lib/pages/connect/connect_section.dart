import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/connect_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_reachability.dart';
import 'connect_qr_panel.dart';

class ConnectSection extends StatefulWidget {
  const ConnectSection({super.key});

  @override
  State<ConnectSection> createState() => _ConnectSectionState();
}

class _ConnectSectionState extends State<ConnectSection> {
  ConnectCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit != null) return;
    _cubit = context.read<ConnectCubit>();
    unawaited(_cubit!.openQrSession());
  }

  @override
  void dispose() {
    final cubit = _cubit;
    if (cubit != null && !cubit.isClosed) {
      unawaited(cubit.closeQrSession());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectCubit, ConnectState>(
      builder: (context, state) {
        final cubit = context.read<ConnectCubit>();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PairingCard(state: state, cubit: cubit),
              const SizedBox(height: 16),
              _ReachabilityCard(
                extraEndpoints: state.extraEndpoints,
                relayUrl: state.relayUrl,
                saving: state.saving,
                onSave: ({required extraEndpoints, required relayUrl}) =>
                    cubit.saveSettings(
                      extraEndpoints: extraEndpoints,
                      relayUrl: relayUrl,
                    ),
              ),
              const SizedBox(height: 16),
              _PairedDevicesCard(
                devices: state.pairedDevices,
                onRevoke: cubit.revokeDevice,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.state, required this.cubit});

  final ConnectState state;
  final ConnectCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = state.networkAddresses
        .where((address) => address.address == state.selectedAddress)
        .firstOrNull;
    return TpCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpSectionHeader(title: l10n.connectSettingsSubtitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.connectInterfaceLabel,
                  style: TpTextStyles.of(context).smMedium,
                ),
                const SizedBox(height: 6),
                if (state.networkAddresses.isEmpty)
                  Text(
                    l10n.connectNoNetworkAddress,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  TpSelect<ConnectNetworkAddress>(
                    key: ValueKey(state.selectedAddress),
                    items: state.networkAddresses,
                    initialItem: selected,
                    itemLabel: (address) => address.label,
                    decoration: TpSelectDecorations.themed(context),
                    searchable: false,
                    onChanged: (address) {
                      if (address != null) {
                        unawaited(cubit.selectAddress(address.address));
                      }
                    },
                  ),
                const SizedBox(height: 20),
                if (state.hasError) ...[
                  Text(
                    l10n.connectError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ConnectQrPanel(
                  state: state,
                  onCheckSshd: () => unawaited(cubit.refresh()),
                  onCopyLink: () {
                    final offer = state.offer;
                    if (offer != null) {
                      unawaited(
                        Clipboard.setData(ClipboardData(text: offer.encode())),
                      );
                    }
                  },
                  onRegenerate: () => unawaited(cubit.regenerateQr()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _SaveReachability =
    Future<void> Function({
      required List<SshReachabilityEndpoint> extraEndpoints,
      required String relayUrl,
    });

class _ReachabilityCard extends StatefulWidget {
  const _ReachabilityCard({
    required this.extraEndpoints,
    required this.relayUrl,
    required this.saving,
    required this.onSave,
  });

  final List<SshReachabilityEndpoint> extraEndpoints;
  final String relayUrl;
  final bool saving;
  final _SaveReachability onSave;

  @override
  State<_ReachabilityCard> createState() => _ReachabilityCardState();
}

class _ReachabilityCardState extends State<_ReachabilityCard> {
  final _relayController = TextEditingController();
  final _rows = <_EndpointControllers>[];
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _replaceValues();
  }

  @override
  void didUpdateWidget(_ReachabilityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty &&
        (oldWidget.extraEndpoints != widget.extraEndpoints ||
            oldWidget.relayUrl != widget.relayUrl)) {
      _replaceValues();
    }
  }

  void _replaceValues() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(widget.extraEndpoints.map(_EndpointControllers.fromEndpoint));
    _relayController.text = widget.relayUrl;
  }

  @override
  void dispose() {
    _relayController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  bool get _valid => _rows.every((row) {
    final port = int.tryParse(row.port.text.trim());
    return row.host.text.trim().isNotEmpty &&
        port != null &&
        port >= 1 &&
        port <= 65535;
  });

  void _changed() {
    setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!_valid || widget.saving) return;
    await widget.onSave(
      extraEndpoints: _rows
          .map(
            (row) => SshReachabilityEndpoint(
              kind: SshEndpointKind.extra,
              host: row.host.text.trim(),
              port: int.parse(row.port.text.trim()),
            ),
          )
          .toList(growable: false),
      relayUrl: _relayController.text,
    );
    if (mounted) setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return TpCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpSectionHeader(title: l10n.connectAdvancedTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.connectAdvancedSubtitle,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < _rows.length; index++) ...[
                  _EndpointRow(
                    controllers: _rows[index],
                    hostLabel: l10n.connectExtraHost,
                    portLabel: l10n.connectExtraPort,
                    removeTooltip: l10n.connectRemoveEndpoint,
                    onChanged: _changed,
                    onRemove: () {
                      setState(() {
                        _dirty = true;
                        _rows.removeAt(index).dispose();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TpButton(
                    variant: TpButtonVariant.outline,
                    onPressed: () {
                      setState(() {
                        _dirty = true;
                        _rows.add(_EndpointControllers.empty());
                      });
                    },
                    child: Text(l10n.connectAddEndpoint),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.connectRelayUrl,
                  style: TpTextStyles.of(context).smMedium,
                ),
                const SizedBox(height: 6),
                TpInput(
                  controller: _relayController,
                  decoration: InputDecoration(
                    hintText: l10n.connectRelayUrlHint,
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) => _changed(),
                ),
                if (!_valid) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.connectInvalidEndpoint,
                    style: TextStyle(color: cs.error),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TpButton(
                    onPressed: !_valid || widget.saving
                        ? null
                        : () => unawaited(_save()),
                    child: widget.saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.connectSaveSettings),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.controllers,
    required this.hostLabel,
    required this.portLabel,
    required this.removeTooltip,
    required this.onChanged,
    required this.onRemove,
  });

  final _EndpointControllers controllers;
  final String hostLabel;
  final String portLabel;
  final String removeTooltip;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _LabeledInput(
            label: hostLabel,
            controller: controllers.host,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: _LabeledInput(
            label: portLabel,
            controller: controllers.port,
            keyboardType: TextInputType.number,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 4),
        TpIconButton(
          icon: Icons.delete_outline,
          tooltip: removeTooltip,
          onTap: onRemove,
        ),
      ],
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: TpTextStyles.of(context).smMedium),
        ),
        TpInput(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _EndpointControllers {
  _EndpointControllers({required this.host, required this.port});

  factory _EndpointControllers.empty() => _EndpointControllers(
    host: TextEditingController(),
    port: TextEditingController(text: '22'),
  );

  factory _EndpointControllers.fromEndpoint(SshReachabilityEndpoint endpoint) {
    return _EndpointControllers(
      host: TextEditingController(text: endpoint.host),
      port: TextEditingController(text: endpoint.port.toString()),
    );
  }

  final TextEditingController host;
  final TextEditingController port;

  void dispose() {
    host.dispose();
    port.dispose();
  }
}

class _PairedDevicesCard extends StatelessWidget {
  const _PairedDevicesCard({required this.devices, required this.onRevoke});

  final List<ConnectPairedDevice> devices;
  final Future<void> Function(String deviceId) onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpSectionHeader(title: l10n.connectPairedDevicesTitle),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text(l10n.connectNoPairedDevices),
            )
          else
            for (final device in devices)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  children: [
                    const Icon(Icons.phone_android_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(device.name),
                          Text(
                            device.deviceId,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TpButton(
                      variant: TpButtonVariant.destructive,
                      onPressed: () => unawaited(onRevoke(device.deviceId)),
                      child: Text(l10n.connectRevokeDevice),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

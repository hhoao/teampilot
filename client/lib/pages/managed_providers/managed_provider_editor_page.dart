import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../models/managed_provider.dart';
import '../../widgets/app_toast/app_toast.dart';

class ManagedProviderEditorPage extends StatefulWidget {
  const ManagedProviderEditorPage({this.provider, super.key});

  final ManagedProvider? provider;

  @override
  State<ManagedProviderEditorPage> createState() =>
      _ManagedProviderEditorPageState();
}

class _ManagedProviderEditorPageState extends State<ManagedProviderEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _adapter;
  late final TextEditingController _endpoint;
  late final TextEditingController _responsePath;
  late final TextEditingController _measuresPath;
  late final TextEditingController _requestMapping;
  late final TextEditingController _currency;
  late final TextEditingController _unit;
  late final TextEditingController _decimalPlaces;
  late final TextEditingController _credentialRef;
  late ManagedProviderKind _kind;
  late String _method;
  late bool _enabled;
  late bool _showPercent;
  String? _formError;
  bool _saving = false;

  ManagedProvider? get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    final provider = _provider;
    final endpoint = provider?.endpointConfig;
    final display = provider?.displayConfig;
    _name = TextEditingController(text: provider?.name ?? '');
    _adapter = TextEditingController(text: provider?.adapterId ?? 'http-json');
    _endpoint = TextEditingController(text: endpoint?.url ?? '');
    _responsePath = TextEditingController(text: endpoint?.responsePath ?? '');
    _measuresPath = TextEditingController(text: endpoint?.measuresPath ?? '');
    _requestMapping = TextEditingController(
      text: _prettyJson(endpoint?.body ?? const <String, Object?>{}),
    );
    _currency = TextEditingController(text: display?.currency ?? '');
    _unit = TextEditingController(text: display?.unit ?? '');
    _decimalPlaces = TextEditingController(
      text: display?.decimalPlaces?.toString() ?? '',
    );
    _credentialRef = TextEditingController(text: provider?.credentialRef ?? '');
    _kind = provider?.kind == ManagedProviderKind.unknown
        ? ManagedProviderKind.customHttp
        : provider?.kind ?? ManagedProviderKind.customHttp;
    _method = endpoint?.method.toUpperCase() ?? 'GET';
    _enabled = provider?.enabled ?? true;
    _showPercent = display?.showPercent ?? false;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _adapter,
      _endpoint,
      _responsePath,
      _measuresPath,
      _requestMapping,
      _currency,
      _unit,
      _decimalPlaces,
      _credentialRef,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          provider == null ? 'New Managed Provider' : 'Edit Managed Provider',
        ),
        actions: [
          if (provider != null)
            IconButton(
              key: const Key('managed-provider-delete'),
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (_formError != null) _ErrorBanner(message: _formError!),
              _sectionTitle(context, 'Identity'),
              _field(
                context,
                key: const Key('managed-provider-name'),
                label: 'Name',
                controller: _name,
                hint: 'Visible name',
              ),
              const SizedBox(height: 12),
              _field(
                context,
                key: const Key('managed-provider-adapter'),
                label: 'Adapter',
                controller: _adapter,
                hint: 'http-json or a registered adapter id',
              ),
              const SizedBox(height: 12),
              _labeledControl(
                context,
                label: 'Kind',
                child: TpSelect<ManagedProviderKind>(
                  key: const Key('managed-provider-kind'),
                  items: const [
                    ManagedProviderKind.apiBalance,
                    ManagedProviderKind.subscriptionQuota,
                    ManagedProviderKind.customHttp,
                  ],
                  initialItem: _kind,
                  itemLabel: (kind) => kind.value,
                  onChanged: (value) {
                    if (value != null) setState(() => _kind = value);
                  },
                  decoration: TpSelectDecorations.themed(context),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle(context, 'Endpoint and request mapping'),
              _field(
                context,
                key: const Key('managed-provider-endpoint'),
                label: 'Endpoint URL',
                controller: _endpoint,
                hint: 'https://…',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              _labeledControl(
                context,
                label: 'Method',
                child: TpSelect<String>(
                  key: const Key('managed-provider-method'),
                  items: const ['GET', 'POST'],
                  initialItem: _method,
                  itemLabel: (method) => method,
                  onChanged: (value) {
                    if (value != null) setState(() => _method = value);
                  },
                  decoration: TpSelectDecorations.themed(context),
                  searchable: false,
                ),
              ),
              const SizedBox(height: 12),
              _field(
                context,
                key: const Key('managed-provider-response-path'),
                label: 'Response path',
                controller: _responsePath,
                hint: r'$.data',
              ),
              const SizedBox(height: 12),
              _field(
                context,
                key: const Key('managed-provider-measures-path'),
                label: 'Measures path',
                controller: _measuresPath,
                hint: r'$.data.measures',
              ),
              const SizedBox(height: 12),
              _textarea(
                context,
                key: const Key('managed-provider-request-mapping'),
                label: 'Request body mapping (JSON)',
                controller: _requestMapping,
              ),
              const SizedBox(height: 20),
              _sectionTitle(context, 'Credentials'),
              _field(
                context,
                key: const Key('managed-provider-credential-ref'),
                label: 'Credential reference',
                controller: _credentialRef,
                hint: 'Reference only; secret values are never shown',
                readOnly: true,
              ),
              const SizedBox(height: 8),
              Text(
                _credentialRef.text.trim().isEmpty
                    ? 'No credential configured'
                    : 'Credential configured · secret is masked',
                style: TpTextStyles.of(
                  context,
                ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              _sectionTitle(context, 'Display configuration'),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      context,
                      key: const Key('managed-provider-currency'),
                      label: 'Currency',
                      controller: _currency,
                      hint: 'USD',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      context,
                      key: const Key('managed-provider-unit'),
                      label: 'Unit',
                      controller: _unit,
                      hint: 'requests / tokens',
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: _field(
                      context,
                      key: const Key('managed-provider-decimal-places'),
                      label: 'Decimals',
                      controller: _decimalPlaces,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                key: const Key('managed-provider-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                subtitle: const Text(
                  'Include this provider in refresh actions.',
                ),
                value: _enabled,
                onChanged: (value) => _setEnabled(value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show percentage'),
                value: _showPercent,
                onChanged: (value) => setState(() => _showPercent = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TpButton(
                      key: const Key('managed-provider-save'),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                  if (provider != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TpButton(
                        key: const Key('managed-provider-test-query'),
                        variant: TpButtonVariant.outline,
                        onPressed: _saving ? null : _testQuery,
                        child: const Text('Test query'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required Key key,
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) => _labeledControl(
    context,
    label: label,
    child: TpInput(
      key: key,
      controller: controller,
      decoration: InputDecoration(hintText: hint),
      keyboardType: keyboardType,
      readOnly: readOnly,
    ),
  );

  Widget _textarea(
    BuildContext context, {
    required Key key,
    required String label,
    required TextEditingController controller,
  }) => _labeledControl(
    context,
    label: label,
    child: TpTextarea(
      key: key,
      controller: controller,
      minHeight: 90,
      maxHeight: 180,
      decoration: const InputDecoration(hintText: '{"api_key": "…"}'),
    ),
  );

  Widget _labeledControl(
    BuildContext context, {
    required String label,
    required Widget child,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: TpTextStyles.of(context).smSemibold),
      ),
      child,
    ],
  );

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: TpTextStyles.of(context).lgSemibold),
  );

  Future<void> _save() async {
    final name = _name.text.trim();
    final adapter = _adapter.text.trim();
    final endpoint = _endpoint.text.trim();
    if (name.isEmpty || adapter.isEmpty) {
      setState(() => _formError = 'Name and adapter are required.');
      return;
    }

    final body = _decodeObject(_requestMapping.text);
    final decimalPlaces = int.tryParse(_decimalPlaces.text.trim());
    if (body == null ||
        _requestMapping.text.trim().isNotEmpty &&
            body.isEmpty &&
            _requestMapping.text.trim() != '{}') {
      setState(() => _formError = 'Request mapping must be a JSON object.');
      return;
    }
    if (_decimalPlaces.text.trim().isNotEmpty && decimalPlaces == null) {
      setState(() => _formError = 'Decimal places must be a whole number.');
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = _provider;
    final next = ManagedProvider(
      id: current?.id ?? 'managed-$now',
      name: name,
      kind: _kind,
      adapterId: adapter,
      brand: current?.brand,
      websiteUrl: current?.websiteUrl ?? '',
      endpointConfig: ManagedProviderEndpointConfig(
        url: endpoint,
        method: _method,
        responsePath: _responsePath.text.trim().isEmpty
            ? null
            : _responsePath.text.trim(),
        measuresPath: _measuresPath.text.trim().isEmpty
            ? null
            : _measuresPath.text.trim(),
        body: body ?? const {},
        credentialName: current?.endpointConfig.credentialName,
        credentialField: current?.endpointConfig.credentialField,
        credentialPlacement:
            current?.endpointConfig.credentialPlacement ?? 'header',
        credentialPrefix: current?.endpointConfig.credentialPrefix,
      ),
      credentialRef: current?.credentialRef,
      displayConfig: ManagedProviderDisplayConfig(
        currency: _currency.text.trim().isEmpty ? null : _currency.text.trim(),
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        decimalPlaces: decimalPlaces,
        showPercent: _showPercent,
      ),
      enabled: _enabled,
      createdAt: current == null || current.createdAt == 0
          ? now
          : current.createdAt,
      updatedAt: now,
    );
    final cubit = context.read<ManagedProviderCubit>();
    await cubit.upsert(next);
    if (!mounted) return;
    setState(() => _saving = false);
    if (cubit.state.errorCode != null) {
      setState(() => _formError = cubit.state.errorMessage);
      return;
    }
    AppToast.show(
      context,
      message: 'Managed provider saved.',
      variant: TpToastVariant.success,
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final provider = _provider;
    if (provider == null) return;
    setState(() => _saving = true);
    await context.read<ManagedProviderCubit>().delete(provider.id);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  Future<void> _testQuery() async {
    final provider = _provider;
    if (provider == null) return;
    await context.read<ManagedProviderUsageCubit>().refreshOne(provider.id);
    if (!mounted) return;
    final state = context.read<ManagedProviderUsageCubit>().state;
    if (state.errorCode != null) {
      AppToast.show(
        context,
        message: state.errorMessage ?? 'Unable to query provider usage.',
        variant: TpToastVariant.error,
      );
    } else {
      AppToast.show(
        context,
        message: 'Provider query completed.',
        variant: TpToastVariant.success,
      );
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    final id = _provider?.id;
    if (id == null) return;
    final cubit = context.read<ManagedProviderCubit>();
    if (value) {
      await cubit.enable(id);
    } else {
      await cubit.disable(id);
    }
  }

  static Map<String, Object?>? _decodeObject(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const {};
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on Object {
      return null;
    }
  }

  static String _prettyJson(Map<String, Object?> value) {
    if (value.isEmpty) return '{}';
    return const JsonEncoder.withIndent('  ').convert(value);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('managed-provider-editor-error'),
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}

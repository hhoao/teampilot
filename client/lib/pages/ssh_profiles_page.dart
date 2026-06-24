import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/ssh_profile_cubit.dart';
import '../models/ssh_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../widgets/app_dialog.dart';
import '../models/runtime_target.dart';
import '../services/storage/targets_repository.dart';
import '../widgets/menu/sidebar_action_menu.dart';
import 'ssh_profiles/credential_push_opt_in_tile.dart';
import 'ssh_profile_setup_page.dart';

class SshProfilesPage extends StatelessWidget {
  const SshProfilesPage({super.key, this.embedded = false});

  /// When true, omits [Scaffold] so Android settings shell supplies the app bar.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = _SshProfilesBody(
      embedded: embedded,
      onAdd: () => openSshProfileEditor(context),
      onEdit: (profile) => openSshProfileEditor(context, profile: profile),
      onDelete: (profile) => confirmDeleteSshProfile(context, profile),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Profiles'),
        actions: [
          IconButton(
            tooltip: '新增',
            icon: Icon(Icons.add),
            onPressed: () => openSshProfileEditor(context),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _SshProfilesBody extends StatelessWidget {
  const _SshProfilesBody({
    required this.embedded,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final bool embedded;
  final VoidCallback onAdd;
  final void Function(SshProfile profile) onEdit;
  final Future<void> Function(SshProfile profile) onDelete;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SshProfileCubit>().state;

    if (state.profiles.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: onAdd,
          icon: Icon(Icons.add),
          label: const Text('新增 SSH Profile'),
        ),
      );
    }

    final list = RadioGroup<String>(
      groupValue: state.selectedProfileId,
      onChanged: (value) {
        if (value == null) return;
        context.read<SshProfileCubit>().selectProfile(value);
      },
      child: ListView.separated(
        padding: embedded ? const EdgeInsets.only(bottom: 88) : null,
        itemCount: state.profiles.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final profile = state.profiles[index];
          final selected = profile.id == state.selectedProfileId;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Radio<String>(value: profile.id),
                title: Text(profile.name),
                subtitle: Text(
                  '${profile.username}@${profile.host}:${profile.port}',
                ),
                selected: selected,
                onTap: () {
                  context.read<SshProfileCubit>().selectProfile(profile.id);
                },
                trailing: SidebarActionMenuButton(
                  specs: const [
                    SidebarActionMenuSpec.item(
                      value: _ProfileAction.edit,
                      icon: Icons.edit_outlined,
                      label: '编辑',
                    ),
                    SidebarActionMenuSpec.item(
                      value: _ProfileAction.delete,
                      icon: Icons.delete_outline,
                      label: '删除',
                      destructive: true,
                    ),
                  ],
                  onSelected: (action) {
                    switch (action as _ProfileAction) {
                      case _ProfileAction.edit:
                        onEdit(profile);
                      case _ProfileAction.delete:
                        onDelete(profile);
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _ProfileCredentialOptInTile(profile: profile),
              ),
            ],
          );
        },
      ),
    );

    if (!embedded) return list;

    return Stack(
      children: [
        list,
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: onAdd,
            icon: Icon(Icons.add),
            label: const Text('新增'),
          ),
        ),
      ],
    );
  }
}

Future<void> openSshProfileEditor(
  BuildContext context, {
  SshProfile? profile,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SshProfileSetupPage(
        profileRepository: context.read<SshProfileRepository>(),
        credentialStore: context.read<SshCredentialStore>(),
        initialProfile: profile,
        connectionTester: SshProfileConnectionTester(
          clientFactory: context
              .read<TerminalTransportFactory>()
              .sshClientFactory,
        ),
        onProfileSaved: () {
          context.read<SshProfileCubit>().load();
          Navigator.of(context).maybePop();
        },
      ),
    ),
  );
}

Future<void> confirmDeleteSshProfile(
  BuildContext context,
  SshProfile profile,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppDialogHeader(title: '删除 SSH Profile'),
          const SizedBox(height: 16),
          Text('确定删除 ${profile.name} 吗？保存的凭据也会一并删除。'),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await context.read<SshProfileCubit>().deleteProfile(profile.id);
}

enum _ProfileAction { edit, delete }

/// P3c: per-profile credential-push opt-in, persisted in targets.json under the
/// profile's ssh target id. Loads the current value and writes on toggle.
class _ProfileCredentialOptInTile extends StatefulWidget {
  const _ProfileCredentialOptInTile({required this.profile});
  final SshProfile profile;

  @override
  State<_ProfileCredentialOptInTile> createState() =>
      _ProfileCredentialOptInTileState();
}

class _ProfileCredentialOptInTileState
    extends State<_ProfileCredentialOptInTile> {
  final _repo = TargetsRepository();
  bool _optedIn = false;

  String get _targetId => RuntimeTarget.ssh(widget.profile.id, label: '').id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _repo.isCredentialOptIn(_targetId);
    if (mounted) setState(() => _optedIn = value);
  }

  Future<void> _onChanged(bool next) async {
    await _repo.setCredentialOptIn(_targetId, next);
    if (mounted) setState(() => _optedIn = next);
  }

  @override
  Widget build(BuildContext context) {
    return CredentialPushOptInTile(
      host: widget.profile.host,
      optedIn: _optedIn,
      onChanged: _onChanged,
    );
  }
}

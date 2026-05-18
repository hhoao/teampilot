import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/ssh_profile_cubit.dart';
import '../models/ssh_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh_profile_connection_tester.dart';
import '../services/terminal_transport_factory.dart';
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
            icon: const Icon(Icons.add),
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
          icon: const Icon(Icons.add),
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
          return ListTile(
            leading: Radio<String>(value: profile.id),
            title: Text(profile.name),
            subtitle: Text(
              '${profile.username}@${profile.host}:${profile.port}',
            ),
            selected: selected,
            onTap: () {
              context.read<SshProfileCubit>().selectProfile(profile.id);
            },
            trailing: PopupMenuButton<_ProfileAction>(
              onSelected: (action) {
                switch (action) {
                  case _ProfileAction.edit:
                    onEdit(profile);
                  case _ProfileAction.delete:
                    onDelete(profile);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: _ProfileAction.edit, child: Text('编辑')),
                PopupMenuItem(value: _ProfileAction.delete, child: Text('删除')),
              ],
            ),
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
            icon: const Icon(Icons.add),
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
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除 SSH Profile'),
      content: Text('确定删除 ${profile.name} 吗？保存的凭据也会一并删除。'),
      actions: [
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
  );
  if (confirmed != true || !context.mounted) return;
  await context.read<SshProfileCubit>().deleteProfile(profile.id);
}

enum _ProfileAction { edit, delete }

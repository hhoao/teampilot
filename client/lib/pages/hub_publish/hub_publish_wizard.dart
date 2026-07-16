import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../../services/expert_hub/local_member_template_store.dart';
import '../../services/hub_publish/bundle_provenance_lookup.dart';
import '../../services/hub_publish/github_registry_publisher.dart';
import '../../services/hub_publish/hub_publish_credentials_store.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import '../../services/hub_publish/hub_publish_service.dart';
import 'package:shared_ui/shared_ui.dart';
import 'hub_publish_wizard_steps.dart';

enum HubPublishWizardStep { auth, metadata, gates, confirm, success }

/// Shared publish wizard for [HubPublishKind.expert] and [HubPublishKind.team].
class HubPublishWizard extends StatefulWidget {
  const HubPublishWizard({
    super.key,
    required this.kind,
    required this.publishApi,
    required this.credentials,
    required this.lookup,
    this.member,
    this.team,
    this.remapCandidates = const [],
  });

  final HubPublishKind kind;
  final DiscoverableMember? member;
  final TeamProfile? team;
  final HubPublishApi publishApi;
  final HubPublishCredentialsStore credentials;
  final BundleProvenanceLookup lookup;
  final List<DiscoverableMember> remapCandidates;

  @override
  State<HubPublishWizard> createState() => _HubPublishWizardState();
}

class _HubPublishWizardState extends State<HubPublishWizard> {
  late HubPublishWizardStep _step;
  late final TextEditingController _token;
  late final TextEditingController _slug;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _author;
  late final TextEditingController _tags;

  final Map<String, String> _expertKeyRemap = {};
  String? _stepError;
  String? _publishError;
  var _busy = false;
  var _tokenReady = false;
  HubPublishResult? _result;

  bool get _isTeam => widget.kind == HubPublishKind.team;

  List<String> get _localExpertKeys {
    final team = widget.team;
    if (team == null) return const [];
    return [
      for (final slot in team.roster)
        if (LocalMemberTemplateStore.isLocalKey(slot.expertKey))
          slot.expertKey,
    ];
  }

  List<String> get _nonPortableIds {
    final team = widget.team;
    if (team == null) return const [];
    return widget.lookup
        .resolve(
          skillIds: team.skillIds,
          pluginIds: team.pluginIds,
          mcpServerIds: team.mcpServerIds,
        )
        .nonPortableIds;
  }

  bool get _gatesResolved {
    if (!_isTeam) return true;
    for (final key in _localExpertKeys) {
      final remapped = _expertKeyRemap[key];
      if (remapped == null ||
          remapped.isEmpty ||
          LocalMemberTemplateStore.isLocalKey(remapped)) {
        return false;
      }
    }
    return _nonPortableIds.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _step = HubPublishWizardStep.auth;
    final seedName = widget.member?.name ?? widget.team?.name ?? '';
    final seedDesc =
        widget.member?.description ?? widget.team?.description ?? '';
    final seedCategory = widget.member?.category ?? '';
    final seedAuthor = widget.member?.author ?? '';
    final seedTags = widget.member?.tags.join(', ') ?? '';
    _token = TextEditingController();
    _slug = TextEditingController(text: _suggestSlug(seedName));
    _name = TextEditingController(text: seedName);
    _description = TextEditingController(text: seedDesc);
    _category = TextEditingController(text: seedCategory);
    _author = TextEditingController(text: seedAuthor);
    _tags = TextEditingController(text: seedTags);
    _loadToken();
  }

  Future<void> _loadToken() async {
    final existing = await widget.credentials.resolveToken();
    if (!mounted) return;
    if (existing != null && existing.isNotEmpty) {
      _token.text = existing;
      setState(() => _tokenReady = true);
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _slug.dispose();
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _author.dispose();
    _tags.dispose();
    super.dispose();
  }

  static String _suggestSlug(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Set<String> _parseTags(String raw) => {
    for (final part in raw.split(RegExp(r'[,，]')))
      if (part.trim().isNotEmpty) part.trim(),
  };

  String get _title {
    final l10n = context.l10n;
    return switch (widget.kind) {
      HubPublishKind.expert => l10n.hubPublishExpertTitle,
      HubPublishKind.team => l10n.hubPublishTeamTitle,
    };
  }

  Future<void> _onNext() async {
    if (_busy) return;
    setState(() => _stepError = null);
    switch (_step) {
      case HubPublishWizardStep.auth:
        final token = _token.text.trim();
        if (token.isEmpty) {
          setState(() => _stepError = context.l10n.hubPublishTokenRequired);
          return;
        }
        setState(() => _busy = true);
        try {
          await widget.credentials.saveToken(token);
          if (!mounted) return;
          setState(() {
            _busy = false;
            _tokenReady = true;
            _step = HubPublishWizardStep.metadata;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _stepError = context.l10n.hubPublishTokenSaveFailed;
          });
        }
      case HubPublishWizardStep.metadata:
        final slug = _slug.text.trim();
        if (slug.isEmpty) {
          setState(() => _stepError = context.l10n.hubPublishSlugRequired);
          return;
        }
        if (_isTeam && _category.text.trim().isEmpty) {
          setState(() => _stepError = context.l10n.hubPublishCategoryRequired);
          return;
        }
        setState(() {
          _step = _isTeam
              ? HubPublishWizardStep.gates
              : HubPublishWizardStep.confirm;
        });
      case HubPublishWizardStep.gates:
        if (!_gatesResolved) {
          setState(() {
            _stepError = _nonPortableIds.isNotEmpty
                ? context.l10n.hubPublishNonPortableBlocked
                : context.l10n.hubPublishLocalExpertBlocked;
          });
          return;
        }
        setState(() => _step = HubPublishWizardStep.confirm);
      case HubPublishWizardStep.confirm:
      case HubPublishWizardStep.success:
        break;
    }
  }

  void _onBack() {
    if (_busy) return;
    setState(() {
      _stepError = null;
      _step = switch (_step) {
        HubPublishWizardStep.metadata => HubPublishWizardStep.auth,
        HubPublishWizardStep.gates => HubPublishWizardStep.metadata,
        HubPublishWizardStep.confirm => _isTeam
            ? HubPublishWizardStep.gates
            : HubPublishWizardStep.metadata,
        HubPublishWizardStep.auth || HubPublishWizardStep.success => _step,
      };
    });
  }

  Future<void> _onPublish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _publishError = null;
    });
    try {
      final HubPublishResult result;
      if (_isTeam) {
        final team = widget.team!;
        result = await widget.publishApi.publishTeam(
          team: team.copyWith(
            name: _name.text.trim().isEmpty ? team.name : _name.text.trim(),
            description: _description.text.trim(),
          ),
          slug: _slug.text.trim(),
          category: _category.text.trim(),
          expertKeyRemap: Map<String, String>.from(_expertKeyRemap),
          author: _author.text.trim().isEmpty ? null : _author.text.trim(),
        );
      } else {
        final member = widget.member!;
        final updated = DiscoverableMember(
          key: member.key,
          name: _name.text.trim().isEmpty ? member.name : _name.text.trim(),
          description: _description.text.trim(),
          category: _category.text.trim().isEmpty
              ? member.category
              : _category.text.trim(),
          source: member.source,
          tags: _parseTags(_tags.text),
          member: member.member,
          skillDeps: member.skillDeps,
          pluginDeps: member.pluginDeps,
          mcpDeps: member.mcpDeps,
          author: _author.text.trim().isEmpty
              ? member.author
              : _author.text.trim(),
          originTeamKey: member.originTeamKey,
          updatedAt: member.updatedAt,
        );
        result = await widget.publishApi.publishExpert(
          member: updated,
          slug: _slug.text.trim(),
          author: _author.text.trim().isEmpty ? null : _author.text.trim(),
          category: _category.text.trim().isEmpty
              ? null
              : _category.text.trim(),
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
        _step = HubPublishWizardStep.success;
      });
    } on HubPublishException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _publishError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _publishError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      key: const Key('hub-publish-wizard'),
      scrollable: true,
      maxWidth: 560,
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: _title,
            onClose: _busy ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 16),
          if (_stepError != null) ...[
            Text(
              _stepError!,
              key: const Key('hub-publish-step-error'),
              style: TpTextStyles.of(context).mdColored(
                Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildStepBody(),
          if (_step != HubPublishWizardStep.success)
            TpDialogActions(
              children: [
                if (_step != HubPublishWizardStep.auth)
                  TextButton(
                    key: const Key('hub-publish-back'),
                    onPressed: _busy ? null : _onBack,
                    child: Text(l10n.back),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                if (_step == HubPublishWizardStep.confirm)
                  FilledButton(
                    key: const Key('hub-publish-publish'),
                    onPressed: _busy ? null : _onPublish,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.hubPublishPublish),
                  )
                else
                  FilledButton(
                    key: const Key('hub-publish-next'),
                    onPressed: _busy ? null : _onNext,
                    child: Text(l10n.hubPublishNext),
                  ),
              ],
            )
          else
            TpDialogActions(
              children: [
                FilledButton(
                  key: const Key('hub-publish-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.hubPublishDone),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStepBody() {
    return switch (_step) {
      HubPublishWizardStep.auth => HubPublishAuthStep(
        tokenController: _token,
        hasStoredToken: _tokenReady,
      ),
      HubPublishWizardStep.metadata => HubPublishMetadataStep(
        kind: widget.kind,
        slugController: _slug,
        nameController: _name,
        descriptionController: _description,
        categoryController: _category,
        authorController: _author,
        tagsController: _tags,
      ),
      HubPublishWizardStep.gates => HubPublishGatesStep(
        localExpertKeys: _localExpertKeys,
        nonPortableIds: _nonPortableIds,
        remap: _expertKeyRemap,
        candidates: widget.remapCandidates,
        onRemapChanged: (localKey, publishedKey) {
          setState(() {
            _expertKeyRemap[localKey] = publishedKey;
            _stepError = null;
          });
        },
      ),
      HubPublishWizardStep.confirm => HubPublishConfirmStep(
        kind: widget.kind,
        slug: _slug.text.trim(),
        name: _name.text.trim(),
        category: _category.text.trim(),
        author: _author.text.trim(),
        error: _publishError,
        busy: _busy,
      ),
      HubPublishWizardStep.success => HubPublishSuccessStep(
        prUrl: _result!.prUrl,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: _result!.prUrl));
        },
        onOpen: () async {
          final uri = Uri.tryParse(_result!.prUrl);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
    };
  }
}

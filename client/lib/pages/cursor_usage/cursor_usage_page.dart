import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/cursor_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_pane_insets.dart';
import 'widgets/account_list.dart';
import 'widgets/add_account_dialog.dart';
import 'widgets/range_picker.dart';
import 'widgets/usage_detail.dart';

class CursorUsagePage extends StatefulWidget {
  const CursorUsagePage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<CursorUsagePage> createState() => _CursorUsagePageState();
}

class _CursorUsagePageState extends State<CursorUsagePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CursorUsageCubit>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = BlocBuilder<CursorUsageCubit, CursorUsageState>(
      builder: (context, state) {
        final cubit = context.read<CursorUsageCubit>();
        final styles = TpTextStyles.of(context);
        final cs = Theme.of(context).colorScheme;
        return KeyedSubtree(
          key: AppKeys.cursorUsagePage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.cursorUsageTitle,
                      style: styles.lgBold,
                    ),
                  ),
                  IconButton(
                    key: AppKeys.cursorUsageRefresh,
                    tooltip: context.l10n.cursorUsageRefresh,
                    onPressed: state.isSyncing
                        ? null
                        : () => cubit.refresh(force: true),
                    icon: state.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                  IconButton(
                    key: AppKeys.cursorUsageAddAccount,
                    tooltip: context.l10n.cursorUsageAddAccount,
                    onPressed: () => _addAccount(cubit),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CursorUsageRangePicker(
                range: state.range,
                onChanged: cubit.setRange,
              ),
              const SizedBox(height: 16),
              Expanded(
                child:
                    state.status == CursorUsageStatus.loading &&
                        state.accounts.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : state.status == CursorUsageStatus.error
                    ? Center(
                        child: Text(
                          context.l10n.cursorUsageLoadFailed,
                          style: styles.smColored(cs.error),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CursorUsageAccountList(
                              accounts: state.accounts,
                              selectedAccountId: state.selectedAccountId,
                              syncing: state.syncing,
                              failures: state.failures,
                              billingCycles: state.billingCycles,
                              onSelect: cubit.selectAccount,
                            ),
                            const SizedBox(height: 12),
                            if (state.selectedReport case final report?)
                              CursorUsageDetail(
                                report: report,
                                account: state.selectedAccount,
                                cycle: state
                                    .billingCycles[state.selectedAccountId],
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
    if (widget.embedded) return content;
    return Padding(padding: WorkspacePaneInsets.page, child: content);
  }

  Future<void> _addAccount(CursorUsageCubit cubit) async {
    final result = await showAddCursorAccountDialog(context);
    if (result == null || !mounted) return;
    final ok = await cubit.addAccount(result.$1, label: result.$2);
    if (!mounted) return;
    AppToast.show(
      context,
      message: ok
          ? context.l10n.cursorUsageAddAccountSuccess
          : context.l10n.cursorUsageAddAccountInvalid,
      variant: ok ? TpToastVariant.success : TpToastVariant.error,
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_project.dart';
import '../models/app_session.dart';
import '../models/default_team_roster.dart';
import '../models/team_config.dart';
import '../services/cli/registry/cli_display_name.dart';
import '../services/cli/registry/cli_tool_registry_scope.dart';
import '../repositories/session_repository.dart';
import '../services/storage/app_storage.dart';
import '../services/app/platform_utils.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../utils/project_path_picker.dart';
import '../utils/project_path_utils.dart';
import 'dropdown/app_dropdown_field.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';
import 'dropdown/app_dropdown_decoration.dart';
import 'dropdown/dropdown_menu_item_button.dart';
import 'dropdown/popover/app_popover.dart';
import 'menu/sidebar_action_menu.dart';
import 'project_details_dialog.dart';
import 'app_icon_button.dart';

part 'context_sidebar/context_sidebar_actions.dart';
part 'context_sidebar/context_sidebar_shell.dart';
part 'context_sidebar/context_sidebar_project_selector.dart';
part 'context_sidebar/context_sidebar_session_tile.dart';
part 'context_sidebar/context_sidebar_tiles.dart';

const double _kSidebarSessionTileInset = 12;

/// Matches [_NewChatTile] / [_TeamConfigTile] inner padding for left alignment.
const double _kSidebarNavRowPadding = 10;

# File Tree Panel — Design

## Summary

Replace the hardcoded placeholder `_FileTreePanel` in `right_tools_panel.dart` with a real, interactive file tree that reads from the local filesystem at `TeamConfig.workingDirectory`.

## Decisions

| Dimension | Decision |
|-----------|----------|
| Data source | Local filesystem via `dart:io` |
| Interactions | Browse (expand/collapse), tap file to open in system editor, right-click context menu (copy path, delete) |
| Hidden files | Hidden by default, toggle to show |
| Loading | Lazy — children loaded when folder is expanded |
| State | `FileTreeCubit` (BLoC Cubit) |
| Search | Filter visible nodes by name |

## Architecture

New files:
- `client/lib/cubits/file_tree_cubit.dart` — state: rootPath, expandedPaths, filterText, showHiddenFiles
- `client/lib/widgets/file_tree_node.dart` — recursive `_FileTreeNode` widget

Modified files:
- `client/lib/widgets/right_tools_panel.dart` — `_FileTreePanel` uses `FileTreeCubit` + real file I/O

## Data Flow

```
TeamConfig.workingDirectory
        │
        ▼
FileTreeCubit(rootPath)
        ├─► listDir() ──► Directory.listSync()
        │     ├─ hide dotfiles when showHiddenFiles == false
        │     ├─ filter by filterText
        │     └─ sort: folders first, then alphabetical
        ├─► expand ──► lazy-load children
        ├─► file tap ──► Process.run('xdg-open'/'open'/'start', [path])
        └─► context menu
              ├─ copy path → Clipboard.setData
              └─ delete → confirm dialog → delete
```

## UI

- Title row: "File Tree" label + hidden-files toggle icon + "copy" action
- Search field (existing)
- Working directory path (existing)
- Recursive tree list: indent + expand arrow (folders) + icon + name
- Right-click: `showMenu` with Copy Path / Delete

## Error Handling

| Scenario | Behavior |
|----------|----------|
| workingDirectory missing | Empty state: "Directory unavailable" |
| No read permission | Skip folder silently |
| File open failure | SnackBar with error |
| Delete failure | SnackBar with error |
| Symlink loop | Detect and skip |

## Caveats

- `Directory.listSync()` is synchronous and blocks the UI thread briefly for large directories. For the expected use case (local dev projects), this is acceptable. If performance becomes an issue, switch to `list()` (async) or isolate.
- `Process.run` to open files uses platform-specific commands. `xdg-open` (Linux), `open` (macOS), `start` (Windows) must be dispatched per-platform.

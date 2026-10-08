/// Center-pane mode for a session workbench tab.
///
/// Independent of PTY [ChatTab.isRunning]: a running session may show
/// [chat] while the terminal stays mounted offstage.
enum SessionWorkbenchView { chat, terminal }

/// Maps a logical [toolRef] (e.g. `teambus.send_message`) to an on-wire tool name.
typedef ToolNameResolver = String Function(String toolRef);

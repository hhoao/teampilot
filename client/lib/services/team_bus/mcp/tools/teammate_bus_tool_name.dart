/// Teammate-bus MCP tool names (`tools/call` `params.name`).
enum TeammateBusToolName {
  listTeammates('list_teammates'),
  sendMessage('send_message'),
  readMessages('read_messages'),
  waitForMessage('wait_for_message'),
  addTasks('add_tasks'),
  updateTask('update_task'),
  listTasks('list_tasks'),
  claimTask('claim_task'),
  publishArtifact('publish_artifact'),
  listArtifacts('list_artifacts'),
  fetchArtifact('fetch_artifact');

  const TeammateBusToolName(this.value);

  final String value;

  static TeammateBusToolName? tryParse(String? raw) {
    if (raw == null) return null;
    for (final tool in values) {
      if (tool.value == raw) return tool;
    }
    return null;
  }
}

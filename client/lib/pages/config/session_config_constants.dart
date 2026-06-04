const kSessionPathPersistDebounce = Duration(milliseconds: 400);

/// Temporary: hide runtime mode until multi-mode UX is ready.
const kShowConnectionModeSetting = false;

/// Team sessions use [AppStorage.commonFlashskyaiLlmConfigFile] from the
/// app-level provider catalog; per-session LLM path override is not exposed.
const kShowLlmConfigPathSetting = false;

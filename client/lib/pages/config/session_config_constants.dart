const kSessionPathPersistDebounce = Duration(milliseconds: 400);

/// Team sessions use [AppStorage.commonFlashskyaiLlmConfigFile] from the
/// app-level provider catalog; per-session LLM path override is not exposed.
const kShowLlmConfigPathSetting = false;

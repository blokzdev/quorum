/// Provider metadata shared across surfaces (Model Studio's key field + the Hub's pre-launch key gate).
/// Pure Dart, no Flutter. A hand-mirror of the engine so the desktop and the engine agree on which
/// providers authenticate with a key.
///
/// source of truth: tradingagents/llm_clients/api_key_env.py (PROVIDER_API_KEY_ENV) +
/// tradingagents/llm_clients/openai_client.py (`key_optional` ProviderSpecs). Keep in sync.
library;

/// Provider -> API-key env var. A non-null value means the provider authenticates with a key (Model
/// Studio shows the write-only key field). `null` (bedrock = AWS credential chain, ollama = local)
/// means no key is needed at all.
const Map<String, String?> providerKeyEnv = {
  'openai': 'OPENAI_API_KEY',
  'anthropic': 'ANTHROPIC_API_KEY',
  'google': 'GOOGLE_API_KEY',
  'azure': 'AZURE_OPENAI_API_KEY',
  'bedrock': null,
  'xai': 'XAI_API_KEY',
  'deepseek': 'DEEPSEEK_API_KEY',
  'qwen': 'DASHSCOPE_API_KEY',
  'qwen-cn': 'DASHSCOPE_CN_API_KEY',
  'glm': 'ZHIPU_API_KEY',
  'glm-cn': 'ZHIPU_CN_API_KEY',
  'minimax': 'MINIMAX_API_KEY',
  'minimax-cn': 'MINIMAX_CN_API_KEY',
  'openrouter': 'OPENROUTER_API_KEY',
  'mistral': 'MISTRAL_API_KEY',
  'kimi': 'MOONSHOT_API_KEY',
  'groq': 'GROQ_API_KEY',
  'nvidia': 'NVIDIA_API_KEY',
  'ollama': null,
  'openai_compatible': 'OPENAI_COMPATIBLE_API_KEY',
};

/// Providers whose key is OPTIONAL — the engine marks them `key_optional` and runs without one (a
/// keyless local relay). They show a key field (you may want to set one) but must NOT block a launch.
/// source of truth: openai_client.py ProviderSpec `key_optional=True` (ollama is already keyless above).
const Set<String> providerKeyOptional = {'openai_compatible'};

/// Whether a provider authenticates with a key at all (drives Model Studio's key-field visibility).
bool providerNeedsKey(String provider) => providerKeyEnv[provider] != null;

/// Whether a missing key for this provider should BLOCK a launch — i.e. it needs a key AND that key is
/// not optional. This is the predicate the pre-launch "Needs keys for: …" gate uses, so a keyless
/// local relay (openai_compatible) or a no-key provider (ollama/bedrock) never false-blocks a run.
bool providerRequiresKeyForLaunch(String provider) =>
    providerNeedsKey(provider) && !providerKeyOptional.contains(provider);

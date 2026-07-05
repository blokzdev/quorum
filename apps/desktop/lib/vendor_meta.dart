/// Data-vendor metadata shared across surfaces (the Data-sources picker + the pre-launch key gate +
/// the launch key-merge). A hand-mirror of the engine's per-vendor key requirement so the desktop and
/// the engine agree on which vendors authenticate with a key. Pure Dart, no Flutter.
///
/// source of truth: tradingagents/runtime/isolation.py VENDOR_API_KEY_ENV (also served, live, on
/// GET /catalog/vendors per vendor as `needs_key`/`key_env`). Keep in sync.
library;

/// Data vendor -> the env var its key is injected as. Only these authenticate with a key; yfinance and
/// polymarket are keyless.
const Map<String, String> vendorKeyEnv = {
  'fred': 'FRED_API_KEY',
  'alpha_vantage': 'ALPHA_VANTAGE_API_KEY',
};

/// Whether a data vendor needs a BYO key.
bool vendorNeedsKey(String vendor) => vendorKeyEnv.containsKey(vendor);

/// The keyed vendor for the optional `macro_data` category — always in the effective config (it's the
/// engine default), so its key is merged whenever stored, but it NEVER blocks a launch (macro degrades
/// gracefully without a key). The user "enables macro signals" simply by storing this key.
const String macroVendor = 'fred';

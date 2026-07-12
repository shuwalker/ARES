/**
 * ARES Identity & State Migration Layer
 *
 * This file owns all ARES product identity and performs a one-time migration
 * from legacy "hermes-*" localStorage keys to "ares-*" keys.
 *
 * Everything here is ARES-owned. Hermes and JROS are untouched.
 */

(function() {
  const LEGACY_PREFIX = 'hermes-';
  const NEW_PREFIX = 'ares-';

  const KEYS_TO_MIGRATE = [
    'theme',
    'skin',
    'font-size',
    'webui-session',
    'webui-model',
    'webui-workspace-panel',
    'webui-workspace-panel-pref',
    'rtl',
    'lang',
    'pref-send_key',
    'pref-language',
    'tts-enabled',
    'tts-auto-read',
    'voice-mode-button',
    'tts-engine',
    'tts-voice',
    'tts-rate',
    'tts-pitch'
  ];

  function migrateKey(oldKey, newKey) {
    try {
      const legacyValue = localStorage.getItem(oldKey);
      const newValue = localStorage.getItem(newKey);

      if (legacyValue !== null && newValue === null) {
        localStorage.setItem(newKey, legacyValue);
        // Keep legacy for now (safe one-way migration)
        console.log(`[ARES] Migrated localStorage: ${oldKey} → ${newKey}`);
      }
    } catch (_) {}
  }

  // Run migration once on load
  function runMigration() {
    KEYS_TO_MIGRATE.forEach(key => {
      migrateKey(LEGACY_PREFIX + key, NEW_PREFIX + key);
    });

    // Special case: active session/model keys. The live code standardizes on
    // the upstream 'hermes-webui-*' names (sessions.js/messages.js/ui.js all
    // read them; a partial rename to 'ares-webui-*' split the state and broke
    // session restore). Carry any value saved under the short-lived ares-*
    // names back to the canonical keys.
    migrateKey('ares-webui-session', 'hermes-webui-session');
    migrateKey('ares-webui-model', 'hermes-webui-model');
  }

  // Expose a clean getter that prefers the new namespace
  window.aresGet = function(key, fallback = null) {
    try {
      return localStorage.getItem(NEW_PREFIX + key) ?? localStorage.getItem(LEGACY_PREFIX + key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  };

  window.aresSet = function(key, value) {
    try {
      localStorage.setItem(NEW_PREFIX + key, value);
    } catch (_) {}
  };

  // Run on script load
  runMigration();

  console.log('[ARES] Identity layer initialized (hermes → ares migration complete)');
})();

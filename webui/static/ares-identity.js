/**
 * ARES Identity & State Migration Layer
 *
 * The live code standardizes on upstream's canonical "hermes-*" localStorage
 * names — a partial rename to "ares-*" split persisted state across files and
 * broke session/model/panel restore. This layer performs a one-time migration
 * of any value saved under the short-lived "ares-*" names BACK to the
 * canonical keys, so users of the renamed builds lose nothing.
 *
 * Everything here is ARES-owned. Hermes and JROS are untouched.
 */

(function() {
  const CANONICAL_PREFIX = 'hermes-';
  const RETIRED_PREFIX = 'ares-';

  const KEYS_TO_MIGRATE = [
    'theme',
    'theme-color',
    'skin',
    'font-size',
    'webui-session',
    'webui-model',
    'webui-model-state',
    'webui-workspace-panel',
    'webui-workspace-panel-pref',
    'webui-sidebar-collapsed',
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
      const retiredValue = localStorage.getItem(oldKey);
      const canonicalValue = localStorage.getItem(newKey);

      if (retiredValue !== null && canonicalValue === null) {
        localStorage.setItem(newKey, retiredValue);
        // Keep the old key for now (safe one-way migration)
        console.log(`[ARES] Migrated localStorage: ${oldKey} → ${newKey}`);
      }
    } catch (_) {}
  }

  // Run migration once on load
  function runMigration() {
    KEYS_TO_MIGRATE.forEach(key => {
      migrateKey(RETIRED_PREFIX + key, CANONICAL_PREFIX + key);
    });
  }

  // Expose a clean getter that reads the canonical namespace (with a fallback
  // to any not-yet-migrated retired key)
  window.aresGet = function(key, fallback = null) {
    try {
      return localStorage.getItem(CANONICAL_PREFIX + key) ?? localStorage.getItem(RETIRED_PREFIX + key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  };

  window.aresSet = function(key, value) {
    try {
      localStorage.setItem(CANONICAL_PREFIX + key, value);
    } catch (_) {}
  };

  // Run on script load
  runMigration();

  console.log('[ARES] Identity layer initialized (hermes → ares migration complete)');
})();

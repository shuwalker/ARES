/**
 * ARES island backdrop manager.
 *
 * Browser-local preference (localStorage key: ares-island-backdrop).
 * Defaults: enabled, surfaceOpacity 42%, position top, mode replace.
 *
 * Persists across reloads and re-applies after theme/skin class changes
 * so light/dark toggles never restore solid layout backgrounds.
 */
(function () {
  'use strict';

  var STORAGE_KEY = 'ares-island-backdrop';
  var DEFAULTS = {
    enabled: true,
    surfaceOpacity: 42,
    position: 'top',
    mode: 'replace'
  };

  function clampOpacity(n) {
    n = Number(n);
    if (!Number.isFinite(n)) return DEFAULTS.surfaceOpacity;
    return Math.min(100, Math.max(0, Math.round(n)));
  }

  function readSettings() {
    try {
      var saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
      if (!saved || typeof saved !== 'object') return Object.assign({}, DEFAULTS);
      return {
        enabled: saved.enabled !== false,
        surfaceOpacity: clampOpacity(saved.surfaceOpacity),
        position: ['top', 'center', 'bottom'].indexOf(saved.position) >= 0
          ? saved.position
          : DEFAULTS.position,
        mode: ['backdrop', 'replace', 'overlay'].indexOf(saved.mode) >= 0
          ? saved.mode
          : DEFAULTS.mode
      };
    } catch (_) {
      return Object.assign({}, DEFAULTS);
    }
  }

  var applying = false;

  function applySettings(settings) {
    var enabled = !!settings.enabled;
    var root = document.documentElement;
    var body = document.body;

    applying = true;
    try {
      root.style.setProperty('--island-surface-opacity', settings.surfaceOpacity + '%');

      // html class for early/pending paint; body class for full rules
      root.classList.toggle('island-backdrop-enabled', enabled);
      if (enabled) {
        root.classList.add('island-backdrop-pending');
      } else {
        root.classList.remove('island-backdrop-pending');
      }

      if (body) {
        body.classList.toggle('island-backdrop-enabled', enabled);
        body.classList.remove(
          'island-pos-top',
          'island-pos-center',
          'island-pos-bottom',
          'island-mode-replace',
          'island-mode-overlay',
          'island-mode-backdrop'
        );
        if (enabled) {
          body.classList.add('island-pos-' + (settings.position || 'top'));
          if (settings.mode === 'overlay') body.classList.add('island-mode-overlay');
          else body.classList.add('island-mode-replace');
        }
      }
    } finally {
      applying = false;
    }

    var enabledEl = document.getElementById('islandBackdropEnabled');
    var slider = document.getElementById('islandSurfaceOpacity');
    var output = document.getElementById('islandSurfaceOpacityValue');
    var control = document.getElementById('islandOpacityControl');
    if (enabledEl) enabledEl.checked = enabled;
    if (slider) {
      slider.value = String(settings.surfaceOpacity);
      slider.disabled = !enabled;
    }
    if (output) output.textContent = settings.surfaceOpacity + '%';
    if (control) control.classList.toggle('disabled', !enabled);
  }

  function saveAndApply(settings) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
    } catch (_) {}
    applySettings(settings);
  }

  function bindControls() {
    var settings = readSettings();
    applySettings(settings);

    var enabled = document.getElementById('islandBackdropEnabled');
    var slider = document.getElementById('islandSurfaceOpacity');

    if (enabled && !enabled.dataset.islandBound) {
      enabled.dataset.islandBound = '1';
      enabled.addEventListener('change', function () {
        settings = Object.assign({}, settings, { enabled: enabled.checked });
        saveAndApply(settings);
      });
    }
    if (slider && !slider.dataset.islandBound) {
      slider.dataset.islandBound = '1';
      slider.addEventListener('input', function () {
        settings = Object.assign({}, settings, {
          surfaceOpacity: clampOpacity(slider.value)
        });
        saveAndApply(settings);
      });
    }
  }

  // Re-apply classes after theme/skin mutations so solid skin !important
  // backgrounds never permanently win after a toggle.
  var reapplyTimer = null;
  function scheduleReapply() {
    if (applying) return;
    if (reapplyTimer) clearTimeout(reapplyTimer);
    reapplyTimer = setTimeout(function () {
      reapplyTimer = null;
      if (!applying) applySettings(readSettings());
    }, 0);
  }

  function watchTheme() {
    if (!window.MutationObserver) return;
    var obs = new MutationObserver(function (mutations) {
      if (applying) return;
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type !== 'attributes') continue;
        if (m.attributeName === 'data-skin') {
          scheduleReapply();
          return;
        }
        if (m.attributeName === 'class') {
          // Ignore our own island classes; react to dark / other theme classes
          var prev = m.oldValue || '';
          var next = document.documentElement.className || '';
          var strip = function (s) {
            return s
              .split(/\s+/)
              .filter(function (c) {
                return c && c.indexOf('island-') !== 0;
              })
              .sort()
              .join(' ');
          };
          if (strip(prev) !== strip(next)) {
            scheduleReapply();
            return;
          }
        }
      }
    });
    obs.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class', 'data-skin'],
      attributeOldValue: true
    });

    // system theme preference changes
    try {
      var mq = window.matchMedia('(prefers-color-scheme: dark)');
      var onScheme = function () {
        scheduleReapply();
      };
      if (mq.addEventListener) mq.addEventListener('change', onScheme);
      else if (mq.addListener) mq.addListener(onScheme);
    } catch (_) {}
  }

  // Apply as early as possible (script is deferred — body usually exists)
  applySettings(readSettings());

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      bindControls();
      watchTheme();
    });
  } else {
    bindControls();
    watchTheme();
  }

  window.backgroundManager = {
    readSettings: readSettings,
    applySettings: applySettings,
    saveAndApply: saveAndApply,
    reapply: function () {
      applySettings(readSettings());
    },
    setPosition: function (pos) {
      var s = readSettings();
      s.position = pos;
      saveAndApply(s);
    },
    setMode: function (m) {
      var s = readSettings();
      s.mode = m;
      saveAndApply(s);
    },
    setEnabled: function (on) {
      var s = readSettings();
      s.enabled = !!on;
      saveAndApply(s);
    },
    setSurfaceOpacity: function (n) {
      var s = readSettings();
      s.surfaceOpacity = clampOpacity(n);
      saveAndApply(s);
    }
  };
})();

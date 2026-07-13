/* ARES Characters Panel — sidebar list + main detail view
   Matches the Skills/Profiles panel pattern exactly:
   - Sidebar: panel-head + search + scrollable list of character items
   - Main: header + detail body (card art, traits, backstory) + empty state */

(function () {
  'use strict';

  var _characters = null;
  var _activeCharId = null;
  var _selectedCharId = null;
  var _detailOpen = false;

  // ── Helpers ───────────────────────────────────────────────────────
  function traitColor(val) {
    if (val >= 0.75) return 'good';
    if (val >= 0.5) return 'accent';
    if (val >= 0.25) return 'warn';
    return 'danger';
  }

  function pct(val) {
    return Math.round((val || 0) * 100) + '%';
  }

  function traitBar(label, val) {
    var v = val || 0;
    var cls = traitColor(v);
    return '<div class="char-trait-row">' +
      '<span class="char-trait-label">' + label.replace(/_/g, ' ') + '</span>' +
      '<div class="char-trait-bar"><div class="char-trait-fill ' + cls + '" style="width:' + (v * 100) + '%"></div></div>' +
      '<span class="char-trait-val">' + pct(v) + '</span>' +
      '</div>';
  }

  // ── Sidebar list item (matches .skill-item / .profile-card pattern) ──
  function buildListItem(char) {
    var active = (char.id === _activeCharId) ? ' active' : '';
    var selected = (char.id === _selectedCharId) ? ' active' : '';
    var cls = active || selected;
    return '<div class="char-list-item' + (cls ? ' active' : '') + '" data-char-id="' + char.id + '" onclick="AresCharacters.selectInList(\'' + char.id + '\')">' +
      '<img class="char-list-card" src="/static/persona-cards/' + char.id + '.png" alt="' + char.name + '" onerror="this.style.display=\'none\'">' +
      '<div class="char-list-info">' +
        '<span class="char-list-name">' + char.name + '</span>' +
        '<span class="char-list-role">' + (char.role || '—') + '</span>' +
      '</div>' +
      (char.id === _activeCharId ? '<span class="char-list-badge">ACTIVE</span>' : '') +
      '</div>';
  }

  // ── Main detail view (matches skill detail / profile detail pattern) ──
  function buildDetailView(char) {
    var hexaco = (char.traits || {}).hexaco || {};
    var special = (char.traits || {}).special || {};
    var expression = (char.traits || {}).expression || {};
    var domains = (char.traits || {}).domains || {};

    var hexacoHtml = Object.keys(hexaco).map(function (k) {
      return traitBar(k, hexaco[k]);
    }).join('');

    var specialHtml = Object.keys(special).map(function (k) {
      return traitBar(k, special[k]);
    }).join('');

    var exprHtml = Object.keys(expression).map(function (k) {
      return traitBar(k, expression[k]);
    }).join('');

    var domainsHtml = Object.keys(domains).map(function (k) {
      return traitBar(k, domains[k]);
    }).join('');

    var speechHtml = '';
    if (char.speech_patterns && char.speech_patterns.length) {
      speechHtml = '<div class="char-speech-patterns">' +
        char.speech_patterns.map(function (s) {
          return '<span class="char-speech-chip">' + s + '</span>';
        }).join('') + '</div>';
    }

    var bio = char.backstory || char.description || '';
    var isActive = (char.id === _activeCharId);
    var selectLabel = isActive ? '✓ Active' : 'Set as active';

    return '<div class="char-detail-content">' +
      // Header row: card art + meta
      '<div class="char-detail-hero">' +
        '<img class="char-detail-art" src="' + char.card_url + '" alt="' + char.name + '" onerror="this.style.opacity=0.1">' +
        '<div class="char-detail-meta">' +
          '<h2 class="char-detail-name">' + char.name + '</h2>' +
          '<div class="char-detail-role">' + (char.role || '—') + '</div>' +
          '<div class="char-detail-voice">' + (char.voice_tone || '') + '</div>' +
          (char.description ? '<p class="char-detail-desc">' + char.description + '</p>' : '') +
          '<button class="char-btn-select' + (isActive ? ' active' : '') + '" onclick="AresCharacters.select(\'' + char.id + '\')">' + selectLabel + '</button>' +
        '</div>' +
      '</div>' +
      // Backstory
      (bio ? '<div class="char-detail-bio">' + bio + '</div>' : '') +
      // Traits
      (hexacoHtml ? '<div class="char-trait-section"><h3>Personality (HEXACO)</h3><div class="char-trait-grid">' + hexacoHtml + '</div></div>' : '') +
      (specialHtml ? '<div class="char-trait-section"><h3>Attributes (SPECIAL)</h3><div class="char-trait-grid">' + specialHtml + '</div></div>' : '') +
      (exprHtml ? '<div class="char-trait-section"><h3>Expression</h3><div class="char-trait-grid">' + exprHtml + '</div></div>' : '') +
      (domainsHtml ? '<div class="char-trait-section"><h3>Domains</h3><div class="char-trait-grid">' + domainsHtml + '</div></div>' : '') +
      (speechHtml ? '<div class="char-trait-section"><h3>Speech Patterns</h3>' + speechHtml + '</div>' : '') +
    '</div>';
  }

  // ── Public API ───────────────────────────────────────────────────
  window.AresCharacters = {
    load: function () {
      var listEl = document.getElementById('charsList');
      if (!listEl) return;
      listEl.innerHTML = '<div class="chars-loading"><div class="chars-loading-spinner"></div></div>';

      fetch('/api/ares/characters')
        .then(function (r) { return r.json(); })
        .then(function (data) {
          _characters = data.characters || [];
          if (!_characters.length) {
            listEl.innerHTML = '<div style="padding:16px;color:var(--muted);font-size:13px;text-align:center">No characters found.</div>';
            return;
          }
          return fetch('/api/ares/persona/current').then(function (r) { return r.json(); }).then(function (d) {
            _activeCharId = d.persona_id || '';
            AresCharacters.renderList();
          });
        })
        .catch(function (err) {
          listEl.innerHTML = '<div style="padding:16px;color:var(--muted);font-size:13px">Failed: ' + err.message + '</div>';
        });
    },

    renderList: function () {
      var listEl = document.getElementById('charsList');
      if (!listEl || !_characters) return;
      listEl.innerHTML = _characters.map(buildListItem).join('');

      // The right/main pane is a selected-character detail pane only.
      // Do not render the full character collection here; the list/sidebar owns collection browsing.
      var selectedExists = _selectedCharId && _characters.some(function (c) { return c.id === _selectedCharId; });
      if (!selectedExists) {
        _selectedCharId = null;
        var titleEl = document.getElementById('charDetailTitle');
        var mainEl = document.getElementById('charDetailBody');
        var emptyEl = document.getElementById('charDetailEmpty');
        var selectBtn = document.getElementById('btnCharSelect');
        if (titleEl) titleEl.textContent = '';
        if (mainEl) {
          mainEl.innerHTML = '';
          mainEl.style.display = 'none';
        }
        if (emptyEl) emptyEl.style.display = '';
        if (selectBtn) selectBtn.style.display = 'none';
      }
    },

    filter: function (query) {
      var listEl = document.getElementById('charsList');
      if (!listEl || !_characters) return;
      var q = (query || '').toLowerCase();
      var filtered = _characters.filter(function (c) {
        return !q || c.name.toLowerCase().indexOf(q) >= 0 || (c.role || '').toLowerCase().indexOf(q) >= 0;
      });
      listEl.innerHTML = filtered.map(buildListItem).join('');
    },

    selectInList: function (charId) {
      _selectedCharId = charId;
      AresCharacters.renderList();

      var char = _characters.find(function (c) { return c.id === charId; });
      if (!char) return;

      // Show only the selected character in the right/detail pane.
      var titleEl = document.getElementById('charDetailTitle');
      var bodyEl = document.getElementById('charDetailBody');
      var emptyEl = document.getElementById('charDetailEmpty');
      var selectBtn = document.getElementById('btnCharSelect');

      if (titleEl) titleEl.textContent = char.name;
      if (bodyEl) {
        // Fetch full character data for backstory + speech patterns
        fetch('/api/ares/character?id=' + encodeURIComponent(charId))
          .then(function (r) { return r.json(); })
          .then(function (data) {
            var full = data.character || data;
            var merged = Object.assign({}, char, {
              backstory: full.backstory || char.backstory,
              speech_patterns: full.speech_patterns || char.speech_patterns,
              custom_instructions: full.custom_instructions || char.custom_instructions,
            });
            // Add domains from full traits
            if (full.traits && full.traits.domains) {
              merged.traits = Object.assign({}, char.traits || {}, { domains: full.traits.domains });
            }
            bodyEl.innerHTML = buildDetailView(merged);
            bodyEl.style.display = 'block';
            if (emptyEl) emptyEl.style.display = 'none';
            if (selectBtn) selectBtn.style.display = char.id === _activeCharId ? 'none' : 'inline-flex';
          })
          .catch(function () {
            bodyEl.innerHTML = buildDetailView(char);
            bodyEl.style.display = 'block';
            if (emptyEl) emptyEl.style.display = 'none';
            if (selectBtn) selectBtn.style.display = char.id === _activeCharId ? 'none' : 'inline-flex';
          });
      }
    },

    selectCurrent: function () {
      if (_selectedCharId) AresCharacters.select(_selectedCharId);
    },

    select: function (charId) {
      fetch('/api/ares/persona/set', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ persona_id: charId }),
      })
        .then(function (r) { return r.json(); })
        .then(function () {
          _activeCharId = charId;
          AresCharacters.renderList();
          // Refresh detail view
          if (_selectedCharId) AresCharacters.selectInList(_selectedCharId);
          // Update composer persona chip
          var chip = document.getElementById('composerPersonaLabel');
          if (chip && _characters) {
            var match = _characters.find(function (c) { return c.id === charId; });
            if (match) chip.textContent = match.name;
          }
          if (typeof window.refreshAresIdentity === 'function') {
            window.refreshAresIdentity();
          } else {
            if (typeof applyBotName === 'function') applyBotName();
            if (typeof syncTopbar === 'function') syncTopbar();
          }
        })
        .catch(function (err) {
          console.error('Failed to set character:', err);
        });
    },

    showDetail: function (charId) {
      // Open full-screen overlay (kept for backward compat, but main use is selectInList)
      var overlay = document.getElementById('charDetailOverlay');
      if (!overlay || !_characters) return;
      var char = _characters.find(function (c) { return c.id === charId; });
      if (!char) return;
      overlay.innerHTML = '<div class="char-detail" onclick="event.stopPropagation()">' +
        '<button class="char-detail-close" onclick="AresCharacters.closeDetail()">&times;</button>' +
        buildDetailView(char) +
        '</div>';
      overlay.classList.add('show');
      _detailOpen = true;
    },

    closeDetail: function () {
      var overlay = document.getElementById('charDetailOverlay');
      if (overlay) {
        overlay.classList.remove('show');
        overlay.innerHTML = '';
      }
      _detailOpen = false;
    },
  };

  // Close detail on overlay click + Escape
  document.addEventListener('click', function (e) {
    if (_detailOpen && e.target && e.target.id === 'charDetailOverlay') {
      AresCharacters.closeDetail();
    }
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && _detailOpen) AresCharacters.closeDetail();
  });
})();

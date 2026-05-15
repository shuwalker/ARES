/**
 * @file TranscriptCache class for efficient extraction of token usage and compaction data from JSONL transcript files, with stat-based caching and incremental reads to handle append-only growth without re-reading the entire file. Also extracts API error entries and turn duration system messages for enhanced analytics.
 * @author Son Nguyen <hoangson091104@gmail.com>
 */

const fs = require("fs");

const MAX_CACHE_ENTRIES = 200;

class TranscriptCache {
  constructor(maxEntries = MAX_CACHE_ENTRIES) {
    this._cache = new Map();
    this._maxEntries = maxEntries;
    this._hits = 0;
    this._misses = 0;
  }

  /**
   * Extract token usage and compaction data from a JSONL transcript file.
   * Uses stat-based caching with incremental reads for append-only growth.
   * Returns null if file doesn't exist or has no data.
   */
  extract(transcriptPath) {
    if (!transcriptPath) return null;
    try {
      let stat;
      try {
        stat = fs.statSync(transcriptPath);
      } catch {
        return null;
      }
      const key = transcriptPath;
      const cached = this._cache.get(key);

      // Cache hit: file unchanged (same mtime + size)
      if (cached && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) {
        this._hits++;
        return cached.result;
      }

      this._misses++;
      // File shrunk or first read → full re-read
      if (!cached || stat.size < cached.bytesRead) {
        const result = this._fullRead(transcriptPath);
        this._set(key, {
          mtimeMs: stat.mtimeMs,
          size: stat.size,
          bytesRead: stat.size,
          tokensByModel: result ? this._cloneTokens(result.tokensByModel) : null,
          compaction: result ? this._cloneCompaction(result.compaction) : null,
          errors: result?.errors ? [...result.errors] : null,
          turnDurations: result?.turnDurations ? [...result.turnDurations] : null,
          thinkingBlockCount: result?.thinkingBlockCount || 0,
          usageExtras: result ? this._cloneUsageExtras(result.usageExtras) : null,
          latestModel: result?.latestModel || null,
          result,
        });
        return result;
      }

      // File grew → incremental read from last position
      if (stat.size > cached.bytesRead) {
        const incremental = this._streamRange(transcriptPath, cached.bytesRead, stat.size);
        if (incremental) {
          const merged = this._merge(cached, incremental);
          const hasTokens = Object.keys(merged.tokensByModel).length > 0;
          const hasTurnDurations = merged.turnDurations && merged.turnDurations.length > 0;
          const hasUsageExtras =
            merged.usageExtras &&
            (merged.usageExtras.service_tiers.length > 0 ||
              merged.usageExtras.speeds.length > 0 ||
              merged.usageExtras.inference_geos.length > 0);
          const result = {
            tokensByModel: hasTokens ? merged.tokensByModel : null,
            compaction: merged.compaction,
            errors: merged.errors,
            turnDurations: hasTurnDurations ? merged.turnDurations : null,
            thinkingBlockCount: merged.thinkingBlockCount || 0,
            usageExtras: hasUsageExtras ? merged.usageExtras : null,
            latestModel: merged.latestModel || null,
          };
          if (
            !result.tokensByModel &&
            !result.compaction &&
            !result.errors &&
            !result.turnDurations &&
            !result.thinkingBlockCount &&
            !result.usageExtras &&
            !result.latestModel
          ) {
            this._set(key, {
              mtimeMs: stat.mtimeMs,
              size: stat.size,
              bytesRead: stat.size,
              tokensByModel: null,
              compaction: null,
              errors: null,
              turnDurations: null,
              thinkingBlockCount: 0,
              usageExtras: null,
              latestModel: null,
              result: null,
            });
            return null;
          }
          this._set(key, {
            mtimeMs: stat.mtimeMs,
            size: stat.size,
            bytesRead: stat.size,
            tokensByModel: this._cloneTokens(result.tokensByModel),
            compaction: this._cloneCompaction(result.compaction),
            errors: result.errors ? [...result.errors] : null,
            turnDurations: result.turnDurations ? [...result.turnDurations] : null,
            thinkingBlockCount: result.thinkingBlockCount || 0,
            usageExtras: this._cloneUsageExtras(result.usageExtras),
            latestModel: result.latestModel || null,
            result,
          });
          return result;
        }

        // Only whitespace/newlines appended
        this._set(key, {
          ...cached,
          mtimeMs: stat.mtimeMs,
          size: stat.size,
          bytesRead: stat.size,
        });
        return cached.result;
      }

      // Same size, different mtime — content may have been rewritten (compaction)
      const result = this._fullRead(transcriptPath);
      this._set(key, {
        mtimeMs: stat.mtimeMs,
        size: stat.size,
        bytesRead: stat.size,
        tokensByModel: result ? this._cloneTokens(result.tokensByModel) : null,
        compaction: result ? this._cloneCompaction(result.compaction) : null,
        errors: result?.errors ? [...result.errors] : null,
        turnDurations: result?.turnDurations ? [...result.turnDurations] : null,
        thinkingBlockCount: result?.thinkingBlockCount || 0,
        usageExtras: result ? this._cloneUsageExtras(result.usageExtras) : null,
        latestModel: result?.latestModel || null,
        result,
      });
      return result;
    } catch {
      return null;
    }
  }

  /**
   * Extract only compaction entries from a JSONL file.
   * Replacement for findCompactionsInFile — uses the same cache, no duplicate reads.
   */
  extractCompactions(transcriptPath) {
    const result = this.extract(transcriptPath);
    if (!result || !result.compaction) return [];
    return result.compaction.entries.map((e) => ({ ...e }));
  }

  /**
   * Full re-read using chunked streaming. Avoids materializing the whole file
   * as a single JS string, so files larger than V8's max string length
   * (~512 MiB on 64-bit Node) parse without aborting the process with
   * "FATAL ERROR: v8::ToLocalChecked Empty MaybeLocal".
   */
  _fullRead(filePath) {
    let size;
    try {
      size = fs.statSync(filePath).size;
    } catch {
      return null;
    }
    return this._streamRange(filePath, 0, size);
  }

  /**
   * Sync chunked range reader + line parser.
   * Reads [startOffset, endOffset) in fixed-size chunks, splits on 0x0A bytes,
   * decodes each complete line as UTF-8 (safe: 0x0A never appears inside a
   * UTF-8 multibyte sequence), and feeds it to _consumeLine. Partial trailing
   * bytes between chunks are held in a byte buffer so multibyte characters
   * straddling a chunk boundary are not corrupted. Never builds a string
   * larger than a single line, so V8 string-length limits cannot be hit.
   */
  _streamRange(filePath, startOffset, endOffset) {
    const state = this._initParseState();
    if (endOffset <= startOffset) return this._finalizeState(state);

    const CHUNK = 4 * 1024 * 1024; // 4 MiB
    const MAX_PENDING = 64 * 1024 * 1024; // hard cap on a single line
    const buf = Buffer.allocUnsafe(CHUNK);
    let pending = null; // bytes of partial trailing line not yet terminated by \n
    let pendingLen = 0;
    let pos = startOffset;
    let fd;
    try {
      try {
        fd = fs.openSync(filePath, "r");
      } catch {
        return this._finalizeState(state);
      }

      while (pos < endOffset) {
        const want = Math.min(CHUNK, endOffset - pos);
        let got;
        try {
          got = fs.readSync(fd, buf, 0, want, pos);
        } catch {
          break;
        }
        if (got <= 0) break;
        pos += got;

        let lineStart = 0;
        for (let i = 0; i < got; i++) {
          if (buf[i] !== 0x0a) continue;

          let line;
          if (pendingLen) {
            const need = pendingLen + (i - lineStart);
            const lineBuf = Buffer.allocUnsafe(need);
            pending.copy(lineBuf, 0, 0, pendingLen);
            buf.copy(lineBuf, pendingLen, lineStart, i);
            line = lineBuf.toString("utf8");
            pending = null;
            pendingLen = 0;
          } else {
            line = buf.toString("utf8", lineStart, i);
          }
          if (line.length && line.charCodeAt(line.length - 1) === 13) {
            line = line.slice(0, -1); // strip CR
          }
          if (line) this._consumeLine(line, state);
          lineStart = i + 1;
        }

        if (lineStart < got) {
          const tailLen = got - lineStart;
          const newLen = pendingLen + tailLen;
          if (newLen > MAX_PENDING) {
            // Pathological single line — drop accumulated bytes and skip
            // forward to the next newline rather than OOM. Loss is bounded
            // to one malformed line.
            pending = null;
            pendingLen = 0;
          } else {
            if (!pending) {
              pending = Buffer.allocUnsafe(Math.max(newLen, 8192));
            } else if (pending.length < newLen) {
              const grow = Buffer.allocUnsafe(Math.max(newLen, pending.length * 2));
              pending.copy(grow, 0, 0, pendingLen);
              pending = grow;
            }
            buf.copy(pending, pendingLen, lineStart, got);
            pendingLen = newLen;
          }
        }
      }

      if (pendingLen) {
        let line = pending.toString("utf8", 0, pendingLen);
        if (line.length && line.charCodeAt(line.length - 1) === 13) {
          line = line.slice(0, -1);
        }
        if (line) this._consumeLine(line, state);
      }
    } finally {
      if (fd !== undefined) {
        try {
          fs.closeSync(fd);
        } catch {
          /* ignore */
        }
      }
    }

    return this._finalizeState(state);
  }

  _initParseState() {
    return {
      tokensByModel: {},
      compaction: null,
      errors: [],
      turnDurations: [],
      thinkingBlockCount: 0,
      usageExtras: {
        service_tiers: new Set(),
        speeds: new Set(),
        inference_geos: new Set(),
      },
      // Track the model of the most recent assistant entry. JSONL is
      // append-only and parsed in file order, so the last value seen here is
      // the user's *current* model — used downstream to keep session.model in
      // sync when the user invokes /model mid-session.
      latestModel: null,
    };
  }

  _consumeLine(line, state) {
    if (!line) return;
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      return;
    }

    if (entry.isCompactSummary) {
      if (!state.compaction) state.compaction = { count: 0, entries: [] };
      state.compaction.count++;
      state.compaction.entries.push({
        uuid: entry.uuid || null,
        timestamp: entry.timestamp || null,
      });
    }

    if (entry.type === "system" && entry.subtype === "turn_duration" && entry.durationMs) {
      const turnTs = entry.timestamp
        ? typeof entry.timestamp === "number"
          ? new Date(entry.timestamp).toISOString()
          : entry.timestamp
        : null;
      state.turnDurations.push({ durationMs: entry.durationMs, timestamp: turnTs });
    }

    const msg = entry.message || entry;
    if (msg.type === "error" && msg.error) {
      state.errors.push({
        type: msg.error.type || "unknown_error",
        message: msg.error.message || "Unknown API error",
        timestamp: entry.timestamp || null,
      });
      return;
    }

    if (entry.isApiErrorMessage) {
      const errContent = Array.isArray(entry.message?.content) ? entry.message.content : [];
      const errText = errContent[0]?.text ? errContent[0].text.slice(0, 500) : "Unknown error";
      state.errors.push({
        type: entry.error || "unknown_error",
        message: errText,
        timestamp: entry.timestamp || null,
      });
      return;
    }

    const model = msg.model;
    if (!model || model === "<synthetic>" || !msg.usage) return;
    state.latestModel = model;
    if (!state.tokensByModel[model]) {
      state.tokensByModel[model] = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    }
    state.tokensByModel[model].input += msg.usage.input_tokens || 0;
    state.tokensByModel[model].output += msg.usage.output_tokens || 0;
    state.tokensByModel[model].cacheRead += msg.usage.cache_read_input_tokens || 0;
    state.tokensByModel[model].cacheWrite += msg.usage.cache_creation_input_tokens || 0;

    if (msg.usage.service_tier) state.usageExtras.service_tiers.add(msg.usage.service_tier);
    if (msg.usage.speed) state.usageExtras.speeds.add(msg.usage.speed);
    if (msg.usage.inference_geo && msg.usage.inference_geo !== "not_available") {
      state.usageExtras.inference_geos.add(msg.usage.inference_geo);
    }

    const msgContent = msg.content || [];
    if (Array.isArray(msgContent)) {
      for (const block of msgContent) {
        if (block.type === "thinking") state.thinkingBlockCount++;
      }
    }
  }

  _finalizeState(state) {
    const hasTokens = Object.keys(state.tokensByModel).length > 0;
    const hasErrors = state.errors.length > 0;
    const hasTurnDurations = state.turnDurations.length > 0;
    const hasUsageExtras =
      state.usageExtras.service_tiers.size > 0 ||
      state.usageExtras.speeds.size > 0 ||
      state.usageExtras.inference_geos.size > 0;
    if (
      !hasTokens &&
      !state.compaction &&
      !hasErrors &&
      !hasTurnDurations &&
      !state.thinkingBlockCount &&
      !hasUsageExtras &&
      !state.latestModel
    ) {
      return null;
    }

    const serializedExtras = hasUsageExtras
      ? {
          service_tiers: [...state.usageExtras.service_tiers],
          speeds: [...state.usageExtras.speeds],
          inference_geos: [...state.usageExtras.inference_geos],
        }
      : null;

    return {
      tokensByModel: hasTokens ? state.tokensByModel : null,
      compaction: state.compaction,
      errors: hasErrors ? state.errors : null,
      turnDurations: hasTurnDurations ? state.turnDurations : null,
      thinkingBlockCount: state.thinkingBlockCount,
      usageExtras: serializedExtras,
      latestModel: state.latestModel,
    };
  }

  /**
   * Parse an in-memory JSONL string. Retained for callers that already have
   * the content as a string. Internal extraction paths now use _streamRange
   * directly to avoid the V8 string-length limit on multi-hundred-MiB files.
   */
  _parseContent(content) {
    const state = this._initParseState();
    let start = 0;
    for (let i = 0; i < content.length; i++) {
      if (content.charCodeAt(i) !== 10) continue;
      let line = content.slice(start, i);
      if (line.length && line.charCodeAt(line.length - 1) === 13) line = line.slice(0, -1);
      if (line) this._consumeLine(line, state);
      start = i + 1;
    }
    if (start < content.length) {
      let line = content.slice(start);
      if (line.length && line.charCodeAt(line.length - 1) === 13) line = line.slice(0, -1);
      if (line) this._consumeLine(line, state);
    }
    return this._finalizeState(state);
  }

  _merge(cached, incremental) {
    const tokensByModel = cached.tokensByModel ? this._cloneTokens(cached.tokensByModel) : {};
    if (incremental && incremental.tokensByModel) {
      for (const [model, tokens] of Object.entries(incremental.tokensByModel)) {
        if (!tokensByModel[model]) {
          tokensByModel[model] = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
        }
        tokensByModel[model].input += tokens.input;
        tokensByModel[model].output += tokens.output;
        tokensByModel[model].cacheRead += tokens.cacheRead;
        tokensByModel[model].cacheWrite += tokens.cacheWrite;
      }
    }

    let compaction = cached.compaction ? this._cloneCompaction(cached.compaction) : null;
    if (incremental && incremental.compaction) {
      if (!compaction) compaction = { count: 0, entries: [] };
      compaction.count += incremental.compaction.count;
      compaction.entries.push(...incremental.compaction.entries);
    }

    let errors = cached.errors ? [...cached.errors] : null;
    if (incremental && incremental.errors) {
      if (!errors) errors = [];
      errors.push(...incremental.errors);
    }

    let turnDurations = cached.turnDurations ? [...cached.turnDurations] : null;
    if (incremental && incremental.turnDurations) {
      if (!turnDurations) turnDurations = [];
      turnDurations.push(...incremental.turnDurations);
    }

    const thinkingBlockCount =
      (cached.thinkingBlockCount || 0) + (incremental?.thinkingBlockCount || 0);

    let usageExtras = cached.usageExtras ? this._cloneUsageExtras(cached.usageExtras) : null;
    if (incremental && incremental.usageExtras) {
      if (!usageExtras) {
        usageExtras = { service_tiers: [], speeds: [], inference_geos: [] };
      }
      // Merge and deduplicate
      const merged = {
        service_tiers: new Set([
          ...usageExtras.service_tiers,
          ...incremental.usageExtras.service_tiers,
        ]),
        speeds: new Set([...usageExtras.speeds, ...incremental.usageExtras.speeds]),
        inference_geos: new Set([
          ...usageExtras.inference_geos,
          ...incremental.usageExtras.inference_geos,
        ]),
      };
      usageExtras = {
        service_tiers: [...merged.service_tiers],
        speeds: [...merged.speeds],
        inference_geos: [...merged.inference_geos],
      };
    }

    // JSONL is append-only and parsed in order, so the incremental block's
    // latestModel (when present) is the newest reading — fall back to the
    // previously-cached value when the new chunk had no assistant entries.
    const latestModel = (incremental && incremental.latestModel) || cached.latestModel || null;

    return {
      tokensByModel,
      compaction,
      errors,
      turnDurations,
      thinkingBlockCount,
      usageExtras,
      latestModel,
    };
  }

  _cloneTokens(tokensByModel) {
    if (!tokensByModel) return null;
    const clone = {};
    for (const [model, t] of Object.entries(tokensByModel)) {
      clone[model] = { ...t };
    }
    return clone;
  }

  _cloneCompaction(compaction) {
    if (!compaction) return null;
    return { count: compaction.count, entries: compaction.entries.map((e) => ({ ...e })) };
  }

  _cloneUsageExtras(extras) {
    if (!extras) return null;
    return {
      service_tiers: [...(extras.service_tiers || [])],
      speeds: [...(extras.speeds || [])],
      inference_geos: [...(extras.inference_geos || [])],
    };
  }

  /** Set cache entry with LRU eviction when at capacity */
  _set(key, entry) {
    // Delete first so re-insertion moves key to end of Map iteration order
    this._cache.delete(key);
    this._cache.set(key, entry);
    // Evict oldest entries (first in Map iteration order) if over limit
    while (this._cache.size > this._maxEntries) {
      const oldest = this._cache.keys().next().value;
      this._cache.delete(oldest);
    }
  }

  /** Number of entries currently cached */
  get size() {
    return this._cache.size;
  }

  /** Remove a specific path from cache */
  invalidate(transcriptPath) {
    this._cache.delete(transcriptPath);
  }

  /** Clear all cached entries */
  clear() {
    this._cache.clear();
  }

  /** Return cache stats for diagnostics */
  stats() {
    const total = this._hits + this._misses;
    return {
      size: this._cache.size,
      maxSize: this._maxEntries,
      hits: this._hits,
      misses: this._misses,
      hitRate: total > 0 ? +((this._hits / total) * 100).toFixed(1) : 0,
      keys: [...this._cache.keys()],
    };
  }
}

module.exports = TranscriptCache;

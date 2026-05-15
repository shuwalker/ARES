/**
 * @file stream-json-parser.js
 * @description Newline-delimited JSON line buffer for parsing `claude
 * --output-format stream-json` output. Reassembles arbitrarily chunked stdout
 * into discrete JSON envelopes (one per line). Robust to partial writes;
 * malformed lines are reported via onError but never throw.
 * @author Son Nguyen <hoangson091104@gmail.com>
 */

function createLineParser(onObject, onError) {
  let buf = "";
  return {
    push(chunk) {
      buf += chunk;
      let nlIdx;
      while ((nlIdx = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, nlIdx).trim();
        buf = buf.slice(nlIdx + 1);
        if (!line) continue;
        try {
          onObject(JSON.parse(line));
        } catch (err) {
          if (typeof onError === "function") onError(err, line);
        }
      }
    },
    flush() {
      const tail = buf.trim();
      buf = "";
      if (!tail) return;
      try {
        onObject(JSON.parse(tail));
      } catch (err) {
        if (typeof onError === "function") onError(err, tail);
      }
    },
  };
}

module.exports = { createLineParser };

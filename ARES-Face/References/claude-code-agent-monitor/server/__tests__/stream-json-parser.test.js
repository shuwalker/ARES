/**
 * @file stream-json-parser.test.js
 * @description Unit tests for the newline-delimited JSON line buffer used to
 * parse `claude --output-format stream-json` output. Verifies chunked input,
 * partial lines spanning chunks, malformed lines, empty input, multiple
 * objects per chunk, and flush semantics.
 * @author Son Nguyen <hoangson091104@gmail.com>
 */

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const { createLineParser } = require("../lib/stream-json-parser");

function collect() {
  const objects = [];
  const errors = [];
  const parser = createLineParser(
    (obj) => objects.push(obj),
    (err, raw) => errors.push({ message: err.message, raw })
  );
  return { parser, objects, errors };
}

describe("stream-json-parser", () => {
  it("parses a single complete line", () => {
    const { parser, objects, errors } = collect();
    parser.push('{"type":"system","subtype":"init"}\n');
    assert.equal(errors.length, 0);
    assert.equal(objects.length, 1);
    assert.equal(objects[0].type, "system");
  });

  it("parses multiple lines in one chunk", () => {
    const { parser, objects } = collect();
    parser.push('{"type":"a"}\n{"type":"b"}\n{"type":"c"}\n');
    assert.deepEqual(
      objects.map((o) => o.type),
      ["a", "b", "c"]
    );
  });

  it("reassembles a JSON object split across two chunks", () => {
    const { parser, objects } = collect();
    parser.push('{"type":"split","val":');
    parser.push('"hello"}\n');
    assert.equal(objects.length, 1);
    assert.equal(objects[0].val, "hello");
  });

  it("reassembles a JSON object split across many small chunks", () => {
    const { parser, objects } = collect();
    const full = '{"type":"chunky","payload":{"deep":{"nested":[1,2,3]}}}\n';
    for (const ch of full) parser.push(ch);
    assert.equal(objects.length, 1);
    assert.deepEqual(objects[0].payload.deep.nested, [1, 2, 3]);
  });

  it("ignores blank lines between objects", () => {
    const { parser, objects, errors } = collect();
    parser.push('{"type":"a"}\n\n\n{"type":"b"}\n');
    assert.equal(objects.length, 2);
    assert.equal(errors.length, 0);
  });

  it("reports malformed JSON via onError without throwing", () => {
    const { parser, objects, errors } = collect();
    parser.push("not valid json\n");
    parser.push('{"type":"ok"}\n');
    assert.equal(objects.length, 1);
    assert.equal(objects[0].type, "ok");
    assert.equal(errors.length, 1);
    assert.match(errors[0].raw, /not valid json/);
  });

  it("does not emit a partial line until newline arrives", () => {
    const { parser, objects } = collect();
    parser.push('{"type":"unfinished"');
    assert.equal(objects.length, 0);
    parser.push("}\n");
    assert.equal(objects.length, 1);
  });

  it("flush() emits trailing line without newline", () => {
    const { parser, objects } = collect();
    parser.push('{"type":"trailing"}');
    assert.equal(objects.length, 0);
    parser.flush();
    assert.equal(objects.length, 1);
    assert.equal(objects[0].type, "trailing");
  });

  it("flush() on empty buffer is a no-op", () => {
    const { parser, objects, errors } = collect();
    parser.flush();
    assert.equal(objects.length, 0);
    assert.equal(errors.length, 0);
  });

  it("flush() reports malformed trailing line via onError", () => {
    const { parser, objects, errors } = collect();
    parser.push("garbage{not-json");
    parser.flush();
    assert.equal(objects.length, 0);
    assert.equal(errors.length, 1);
  });

  it("works without onError callback when input is malformed", () => {
    let count = 0;
    const parser = createLineParser((_o) => count++);
    // No throw expected.
    parser.push("garbage\n");
    parser.push('{"type":"ok"}\n');
    assert.equal(count, 1);
  });

  it("handles CRLF line endings cleanly (\\r is trimmed before parse)", () => {
    const { parser, objects, errors } = collect();
    parser.push('{"type":"crlf"}\r\n');
    // Note: parser only splits on \n; the \r at end of line stays in the
    // line. JSON.parse tolerates trailing whitespace including \r.
    assert.equal(errors.length, 0);
    assert.equal(objects.length, 1);
    assert.equal(objects[0].type, "crlf");
  });

  it("handles a stream-json envelope with stream_event sub-event shape", () => {
    const { parser, objects } = collect();
    const env = JSON.stringify({
      type: "stream_event",
      event: {
        type: "content_block_delta",
        index: 0,
        delta: { type: "text_delta", text: "Hello" },
      },
      session_id: "sess",
    });
    parser.push(env + "\n");
    assert.equal(objects.length, 1);
    assert.equal(objects[0].event.delta.text, "Hello");
  });
});

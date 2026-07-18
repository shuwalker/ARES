# plugin-llm-example

Reference plugin showing host-owned structured LLM access via
`ctx.llm.complete_structured()`. The plugin never sees provider
credentials — it asks the host to run a one-shot completion against
whatever model and auth the user has active.

## What it does

Adds a `/receipt-extract <path>` slash command that turns a receipt
(plain text file OR image file) into a structured JSON record:

```json
{
  "vendor": "Acme Coffee",
  "total": 4.75,
  "currency": "USD",
  "tags": ["coffee", "breakfast"]
}
```

## How it works

```python
result = ctx.llm.complete_structured(
    instructions="Extract a structured receipt record...",
    input=[{"type": "image", "data": img_bytes, "mime_type": "image/png"}],
    json_schema=RECEIPT_SCHEMA,
    schema_name="receipt.record",
    purpose="plugin-llm-example.extract_receipt",
    temperature=0.0,
    max_tokens=512,
)
print(result.parsed)  # → dict matching the schema
```

The host:

* resolves the active provider + model from the user's config,
* picks the right vision-capable model when image input is supplied,
* enforces the request timeout,
* applies the trust gate (model/agent/profile overrides require
  explicit per-plugin opt-in in `config.yaml`),
* parses the JSON response and validates it against the supplied
  schema before returning.

The plugin only needs to know about `ctx.llm`. Everything else —
auth, routing, retries, fallback — stays on the host side of the
boundary.

## Try it

Clone this repo (or download just this directory), drop it into your user-plugins folder, and enable it:

```bash
git clone https://github.com/NousResearch/hermes-example-plugins.git
cp -r hermes-example-plugins/plugin-llm-example ~/.hermes/plugins/
hermes plugins enable plugin-llm-example
```

Then in a Hermes session:

```
/receipt-extract /path/to/receipt.png
/receipt-extract /path/to/receipt.txt
```

## Trust-gate config (optional)

Default behaviour: the plugin runs against the user's active model
and cannot override anything. If you want to pin extraction to a
cheaper model, add to `config.yaml`:

```yaml
plugins:
  entries:
    plugin-llm-example:
      llm:
        allow_model_override: true
        allowed_models:
          - openai/gpt-4o-mini
          - anthropic/claude-3-5-haiku
```

The plugin then accepts `model="openai/gpt-4o-mini"` etc.

See `website/docs/developer-guide/plugin-llm-access.md` for the full
API reference.

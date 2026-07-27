# Architecture Decision Records

Short records of decisions that shape the ARES runtime, and the reasoning behind
them. They exist so the next maintainer — human or agent — does not have to
re-derive intent from code, or silently reverse a decision that was deliberate.

Write one when a choice is **load-bearing and non-obvious**: something a reasonable
person would otherwise "fix" the other way.

| ADR | Decision |
|---|---|
| [0001](./0001-subprocess-workers.md) | Workers run as subprocesses, not in-process |
| [0002](./0002-two-store-model.md) | ARES owns its store; workers own theirs |
| [0003](./0003-read-only-means-no-write-back.md) | `read_only` marks absence of a write-back path |
| [0004](./0004-translator-layer.md) | Frontend consumes ARES contracts, never framework shapes |
| [0005](./0005-sse-streaming.md) | Streaming uses SSE, inherited from upstream |

Format: context, decision, consequences, and what would justify revisiting it.

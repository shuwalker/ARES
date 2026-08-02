# macOS Agent Guide

Read the repository [`AGENTS.md`](../../AGENTS.md) first.

## Scope

`apps/macos/` contains the native SwiftUI/AppKit application and ARESCore.

## Rules

- Keep the menu-bar lifecycle (`LSUIElement`) and activation-policy behavior
  intact unless the task explicitly changes it.
- Route runtime behavior through ARESCore protocols; do not hardcode worker
  implementation logic in views.
- The native app and Web UI are clients of the same ARES contracts. Product
  concepts and setting ownership must remain aligned.
- Export canonical Jaeger environment names. Strip inherited legacy variables
  before launching the controller.
- Do not add Python, Node dependencies, or copied Web sources here.

## Verification

Run `swift test` from the repository root. Use `./apps/macos/build-app.sh` only
when packaging or app-bundle behavior changes.

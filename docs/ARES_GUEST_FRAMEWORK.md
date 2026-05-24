# ARES Guest Framework — Design Sketch

Status: **Draft, undecided.** Read, push back, then we build.

## Why this exists

The Hub tab is meant to host other apps inside ARES. Today it does that by
forking the Hermes Desktop source into `ARES-Desktop/Sources/ARES/Dodo/` and
mounting `RootView` via an `NSHostingController` wrapper. Two problems:

1. **Forking doesn't scale.** Every new app we want to host would need its
   source pulled in and patched (see PR #11, where embedding required adding
   an `isEmbedded` flag to `RootView` to stop its toolbar bleeding into the
   ARES window).
2. **Fork loses upstream updates.** The real Hermes Desktop self-updates from
   the original team. Our `Dodo/` copy doesn't. Same problem applies to
   Blender, VTuber apps, etc. — we'd never want to fork those.

A Guest Framework lets Hub host any app — web pages, in-process Swift, native
Mac apps, remote desktops — through a single contract, without modifying the
guest's source.

## The shape

```swift
protocol GuestApp: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: NSImage? { get }
    func makeView() -> NSView      // what Hub mounts
    func activate()                // called when tab becomes visible
    func deactivate()              // called when tab leaves visible
    func terminate()               // app quit / Hub removal
}

@MainActor
final class GuestAppRegistry: ObservableObject {
    @Published private(set) var guests: [any GuestApp] = []
    func register(_ guest: any GuestApp) { ... }
    func unregister(id: String) { ... }
}
```

Hub becomes ~50 lines: a tab bar driven by `registry.guests`, a container
that mounts the active guest's view. No per-guest knowledge.

## Guest types and macOS reality

| Type | Mechanism | Works for | Honest tradeoffs |
|---|---|---|---|
| **WebGuest** | `WKWebView` pointed at URL / local server | Hermes WebUI (today), VRoid Hub, n8n, dashboards, any browser VTuber | Clean. No leakage. The pattern that already works in Hub. |
| **NativeSwiftUIGuest** | `NSHostingView` wrapping a SwiftUI `View` | In-process views we own (Companion, Office, the current Dodo RootView) | Still in-process. Window-level modifiers (`.toolbar`, `.commands`, `.alert`) bubble up unless guest is written with `isEmbedded` discipline. We control the views, so this is fine. |
| **ProcessWindowGuest** | Launch app as child process, capture window via `ScreenCaptureKit`, forward input via `CGEvent` + Accessibility | Blender, VSeeFace, DaVinci Resolve, any standalone Mac app | macOS does **not** support cross-process window reparenting. Best we get is a live video stream of the window at ~16–33 ms latency, with input forwarded back. Needs Screen Recording + Accessibility permissions. Feels slightly off for fast input (drag-select, painting). |
| **RemoteDisplayGuest** | VNC / RDP / Sunshine client embedded as `NSView` | RackPC, other Macs over Tailscale, Linux boxes | Latency depends on protocol + network. Easiest path: embed an existing client lib. |
| **CoordinationGuest** | Launch / focus / message external app via `NSWorkspace` + URL schemes; tab shows controls + screenshot preview | Anything where embedding isn't worth it | Most honest option for big native apps. The guest's real window stays separate; ARES just *coordinates* it. |

## The fork-vs-host decision for Hermes Desktop

Two roads:

**A. Keep `Dodo/` (the fork).**
- ARES has total control over the embedded UI; we can keep patching `isEmbedded`-style flags.
- Lose upstream Hermes Desktop updates. Every Hermes Desktop release means a manual merge into `Dodo/`.
- `NativeSwiftUIGuest` is the right framework slot for it.

**B. Delete `Dodo/`. Host the real Hermes Desktop binary.**
- Get upstream self-updates for free.
- `NativeSwiftUIGuest` is no longer applicable — Hermes Desktop is a separate process. Options become `ProcessWindowGuest` (laggy, permission-heavy) or `CoordinationGuest` (launch standalone, ARES shows status).
- Big up-front work: process spawn, ScreenCaptureKit pipeline, input forwarding, permission UX.
- Bonus: the same machinery unlocks Blender, VTuber, etc.

**Recommendation:** Start with **A as a stopgap** (PR #11 already gets us there), but design the framework so **B is reachable**. Concretely:

1. Land the Guest protocol + registry + `WebGuest` + `NativeSwiftUIGuest` first. Migrate today's Hub (WebUI, Settings, Hermes Desktop) onto it. Hermes Desktop tab uses `NativeSwiftUIGuest(Dodo.RootView)`. PR #11's `isEmbedded` flag stays — it's exactly what `NativeSwiftUIGuest`-hosted views need.
2. Add `CoordinationGuest` next. Cheap, immediately useful for Blender / DaVinci. Tab shows "Open in Blender" + last screenshot.
3. Build `ProcessWindowGuest` only if (2) proves insufficient — i.e. you actually want a live embedded Blender window, not just a coordinated one. This is the expensive path; defer it.
4. Decision on B (delete `Dodo/`, host upstream Hermes Desktop binary): defer until `ProcessWindowGuest` or `CoordinationGuest` is real. Until then, stay forked.

## What this means for PR #11

Keep it. It's not wasted — `NativeSwiftUIGuest` will need exactly that `isEmbedded` flag on every in-process SwiftUI guest. Mark it as "step 0 of the Guest Framework" in the PR description and merge when comfortable.

## Followups (track here so they don't get lost)

- **Claude endpoint patch.** Owner reports the Claude subscription won't talk
  to the current endpoint. Need to: (a) confirm which endpoint (Anthropic
  official API vs. local proxy), (b) capture the exact error, (c) patch the
  client config or proxy headers. Blocking item — without this, owner can't
  drive ARES with Claude.
- **`NativeGuestHost` cleanup.** The current implementation uses
  `NSHostingController` + manual constraints + a Coordinator. Once
  `NativeSwiftUIGuest` exists, replace with a plain `NSHostingView` and delete
  the wrapper. (`NSHostingView` is the supported AppKit-embed-SwiftUI path.)
- **Toolbar leak audit.** Beyond `.toolbar`, check `HermesDesktopCommands.swift`
  for `.commands { ... }` and any `.alert` / `.sheet` on `WindowGroup`. They
  all bubble to the host window in the same way. Same `isEmbedded` discipline
  applies.

## What I am NOT proposing

- Big-bang rewrite of Hub.
- Pulling `Dodo/` out before we have a real replacement.
- Building `ProcessWindowGuest` speculatively.
- Adding more "Coming Soon" tabs.

Build only the slot we need next. Each guest type is a single file; we can add
them one at a time.

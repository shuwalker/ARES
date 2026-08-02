# System Settings

| Attribute | Value |
| --- | --- |
| **Status** | Planned / partially implemented |
| **Owner** | Web Settings, native macOS app, and controller lifecycle |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Linked source, native capability, and acceptance tests |

## User purpose

System Settings answers: **How should the ARES application and its local
runtime behave on this computer?** It is configuration, not a live operations
dashboard.

The current UI label is **App**. The intended label is **System** once the
native and runtime controls below are represented accurately.

## Ownership boundary

System Settings owns:

- Launch at login, menu-bar presence, and background operation.
- Global quick-launch and open-window shortcuts.
- Default startup destination and window behavior.
- Local ARES controller status, address/port, start, stop, and restart.
- Update channel, application updates, and installed extensions.
- Local diagnostics, preference reset, and safe service recovery.

Control Center owns live agents, delegated tasks, AI workers and tools,
connected services and devices, approvals, memory/privacy, autonomy, activity,
and alerts. A summary may link across the boundary, but a setting has one owner.

## Intended page layout

1. **Desktop integration** — launch at login, menu bar, background operation,
   and global shortcuts.
2. **Startup** — default destination, window restoration, and login behavior.
3. **Local runtime** — honest service state with start/stop/restart controls and
   the effective address/port.
4. **Updates and extensions** — versions, update channel, extensions, and native
   application availability.
5. **Maintenance** — diagnostics, reset preferences, and recovery actions with
   confirmation appropriate to their impact.

## Product rules

- Web and macOS surfaces configure the same ARES-owned settings where a shared
  setting exists.
- Native-only controls must report when the web client cannot apply them.
- A preference hint must not pretend a native capability changed successfully.
- Service controls target the ARES controller, never a legacy Hermes process.
- Worker-specific configuration such as Jaeger AI remains an AI-tool concern in
  Control Center; System Settings owns the ARES service that connects to it.
- Restart and reset actions show their scope and preserve user-owned data unless
  the user explicitly chooses a destructive reset.

## Implementation status

- Implemented: Web App section with access, update, extension, connection
  summary, version, and a menu-bar preference hint.
- Implemented: native ARES process and controller management primitives.
- Missing: one shared contract proving which native controls are effective.
- Missing: global shortcut, launch-at-login, background, and complete local
  service controls in the Settings UI.
- Needs refinement: rename App to System only when the page fulfills the broader
  contract.

## Source anchors

| Concern | Source |
| --- | --- |
| Current Web section | `apps/web/src/features/settings/AppSection.tsx` |
| Settings controller | `apps/web/src/features/settings/useSettingsController.ts` |
| Native application lifecycle | `apps/macos/Sources/ARES/ARESApp.swift` |
| Native controller lifecycle | `apps/macos/Sources/ARES/WebUIServerManager.swift` |
| Native configuration | `apps/macos/Sources/ARESCore/Services/ARESConfiguration.swift` |
| Controller settings route | `services/controller/fastapi_app/routers/settings.py` |

## Acceptance criteria

- A user can understand which controls affect this Mac versus every ARES client.
- Menu-bar, login, background, and shortcut controls reflect actual native state.
- The local controller can be inspected and safely restarted without targeting
  Hermes or an external worker process.
- UI state reports success only after the owning native/controller API confirms
  the change.
- Control Center does not duplicate System-owned configuration controls.
- Web and macOS clients explain capability differences instead of silently
  ignoring unsupported changes.

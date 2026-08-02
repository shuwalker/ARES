# System Settings

| Attribute | Value |
| --- | --- |
| **Status** | Active / partially implemented |
| **Owner** | Web Settings, native macOS app, and controller lifecycle |
| **Last verified** | 2026-08-01 |
| **Source of truth** | Linked source, native capability, and acceptance tests |

## User purpose

System Settings answers: **How should the ARES application and its local
runtime behave on this computer?** It is configuration, not a live operations
dashboard.

The Web UI label is **System**. Its route/deep-link identifier remains `app` for
compatibility with existing links and stored navigation state.

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

- Implemented: modular Web System section with desktop integration, local
  runtime, access, updates, extensions, and maintenance cards.
- Implemented: typed desired/effective contract shared by Web, controller, and
  the native app. Disconnected Web clients cannot claim native changes worked.
- Implemented: menu-bar presence, login launch through `SMAppService`, global
  Command-Shift-Space quick launch, background policy, controller status, and
  Mac-owned restart.
- Implemented: the Mac app refuses to adopt a pre-existing process on the ARES
  port and marks its controller with a per-launch ownership instance.
- Missing: default startup destination, editable shortcut choices, preference
  reset, and complete diagnostic export.

## Source anchors

| Concern | Source |
| --- | --- |
| Web route section | `apps/web/src/features/settings/SystemSection.tsx` |
| Web contract | `apps/web/src/shared/system-settings-contract.ts` |
| Desktop integration | `apps/web/src/features/settings/DesktopIntegrationCard.tsx` |
| Local runtime | `apps/web/src/features/settings/LocalRuntimeCard.tsx` |
| Settings controller | `apps/web/src/features/settings/useSettingsController.ts` |
| Native desired/effective bridge | `apps/macos/Sources/ARES/NativeSystemBridge.swift` |
| Native application lifecycle | `apps/macos/Sources/ARES/ARESApp.swift` |
| Native controller lifecycle | `apps/macos/Sources/ARES/WebUIServerManager.swift` |
| Native configuration | `apps/macos/Sources/ARESCore/Services/ARESConfiguration.swift` |
| Controller contract policy | `services/controller/api/native_system.py` |
| Controller route | `services/controller/fastapi_app/routers/native_system.py` |
| Web contract tests | `apps/web/src/shared/system-settings-contract.test.ts` |
| Native tests | `apps/macos/Tests/ARESTests/NativeSystemBridgeTests.swift` |
| Controller tests | `services/controller/tests/test_native_system_settings.py` |

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

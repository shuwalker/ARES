# Extraction Report: hermes-desktop

**Source:** hermes-desktop
**Language:** Swift
**Files:** 154
**Date:** 2026-06-24 00:51

## Architecture Patterns
- AppState.swift: MVVM/Observable
- AppState.swift: Async/Await
- HermesDesktopCommands.swift: Async/Await

## Protocols

## Key Types & Patterns
- `enum CodingKeys: String, CodingKey {`
- `struct CronJobListResponse: Codable {`
- `struct CronJob: Codable, Identifiable, Hashable, OptionalModelDisplayable {`
- `enum CodingKeys: String, CodingKey {`
- `enum CronJobState: Codable, Hashable {`
- `enum CronScheduleFormatter {`

## Key Files
- hermes-desktop/Package.swift
- hermes-desktop/Sources/HermesDesktop/App/AppState.swift
- hermes-desktop/Sources/HermesDesktop/App/HermesApplicationDelegate.swift
- hermes-desktop/Sources/HermesDesktop/App/HermesDesktopApp.swift
- hermes-desktop/Sources/HermesDesktop/App/HermesDesktopCommands.swift
- hermes-desktop/Sources/HermesDesktop/Models/AppAlert.swift
- hermes-desktop/Sources/HermesDesktop/Models/AppSection.swift
- hermes-desktop/Sources/HermesDesktop/Models/ConnectionProfile.swift
- hermes-desktop/Sources/HermesDesktop/Models/CronJobModels.swift
- hermes-desktop/Sources/HermesDesktop/Models/FileEditorDocument.swift

---
*Auto-extracted by extraction pipeline*

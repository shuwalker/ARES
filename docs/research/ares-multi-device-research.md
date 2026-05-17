# ARES Multi-Device Architecture Research

## 1. Multi-Platform SwiftUI: Single Target vs. Multi-Target Architecture

### Current Best Practice (Xcode 15+, iOS 17/macOS 14+)

Apple's modern recommendation is the **multi-platform single target** approach using the `.platforms()` manifest modifier in the Swift Package or multi-platform app template.

#### Option A: Single Xcode Project with Multi-Platform Target (Recommended for ARES)

```
ARES-Face/
├── ARES-Face.xcodeproj
├── ARES-Face/
│   ├── ARES_FaceApp.swift          // @main entry point with conditional compilation
│   ├── Shared/
│   │   ├── Models/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   └── BrainAdapter.swift      // Protocol stays universal
│   ├── macOS/
│   │   ├── MetalAvatarView.swift   // macOS-specific renderer
│   │   └── MenuBarExtras.swift
│   ├── iOS/
│   │   └── TouchInputModifiers.swift
│   ├── watchOS/
│   │   ├── WatchBrainClient.swift  // Simplified adapter
│   │   └── VoiceOnlyView.swift     // Voice-first UI
│   └── tvOS/                       // Future expansion
└── Packages/
    ├── ARESKit/                    // SPM package for shared code
    └── ARESNetwork/                // WebSocket + REST clients
```

#### Xcode Project Configuration

1. **Create a Multi-Platform App** (Xcode 15+): File → New → Project → Multiplatform App
2. **Supported Destinations**: Add iPhone, iPad, Mac, Apple Watch, Apple TV in Target Settings
3. **Conditional Compilation**:
```swift
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
typealias PlatformImage = UIImage
#endif
```

4. **Scene Structure** (ARES_FaceApp.swift):
```swift
@main
struct ARES_FaceApp: App {
    @StateObject private var brain = BrainConnection()
    
    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("ARES", systemImage: "brain") {
            CompactChatView()
                .environmentObject(brain)
        }
        WindowGroup {
            MainChatView()
                .environmentObject(brain)
        }
        #elseif os(watchOS)
        WindowGroup {
            WatchChatView()
                .environmentObject(brain)
        }
        #else
        WindowGroup {
            MainChatView()
                .environmentObject(brain)
        }
        #endif
    }
}
```

#### Shared Module (Swift Package)

Extract pure Swift logic into an SPM package for testability and reuse:

```swift
// Package.swift
let package = Package(
    name: "ARESKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "ARESKit", targets: ["ARESKit"]),
        .library(name: "ARESNetwork", targets: ["ARESNetwork"]),
    ],
    targets: [
        .target(name: "ARESKit"),
        .target(name: "ARESNetwork", dependencies: ["ARESKit"])
    ]
)
```

**Key Rule**: Keep `ARESNetwork` free of UIKit/SwiftUI imports so it compiles on watchOS.

---

## 2. WebSocket on Apple Watch: Limitations & Requirements

### Framework Choice
- **URLSession WebSocket Tasks** (iOS 13+/watchOS 6+) — Apple's modern native API
- **Starscream** or **SocketRocket** — third-party alternatives, generally not needed in 2025
- **NWConnection** (Network framework) — lower level, UDP/TCP, more battery control

### Background Execution Reality

Apple Watch background execution is **severely constrained**:

| Scenario | WebSocket Behavior |
|----------|-------------------|
| App in foreground | ✅ Full duplex WebSocket works normally |
| App in background (suspended) | ❌ Connection closed by system within seconds |
| Complication / Dock pinned | ⚠️ `WKApplicationRefreshBackgroundTask` allows ~30s of network |
| Siri intent / notification action | ⚠️ Background execution granted for action duration |
| Always-on display (Series 5+) | App remains visible but may still suspend after idle |

### Critical Limitations

1. **No VoIP Sockets**: Unlike iOS, watchOS does NOT support persistent VoIP background sockets
2. **WatchConnectivity Fallback**: For pushing data TO the watch when app isn't running, use `WCSession` + `updateApplicationContext(_:)` or `transferUserInfo(_:)`
3. **Background Tasks**: Register in Info.plist:
```xml
<key>WKBackgroundModes</key>
<array>
    <string>self-care</string>  // Process data when watch is on charger
</array>
```

4. **NSURLSessionBackgroundConfiguration**: NOT available on watchOS. Standard `URLSession` only.

### Battery Implications

- **WebSocket keep-alive pings**: Use 60-120s intervals (NOT 10-30s). Watch WiFi radio has high power cost.
- **Prefer Coalesced Updates**: Batch multiple conversation state changes into single push
- **Bluetooth LE vs WiFi**: WiFi consumes ~3-4x more power on Apple Watch than BLE pass-through
- **Practical Limitation**: Continuous WebSocket on watch drains ~15-20% battery per hour

### Recommended Architecture for Watch
```swift
enum WatchConnectionMode {
    case realtimeWebSocket  // Only when app foreground + user actively chatting
    case watchConnectivity  // Background updates from iPhone
    case periodicPolling    // Background refresh task every 15-20 min
}
```

---

## 3. Networking: Watch → Mac Studio Brain

### Three Pathways Compared

| Approach | Latency | Battery Impact | Works Without iPhone? | Complexity |
|----------|---------|----------------|----------------------|------------|
| **Direct WiFi WebSocket** (watch↔Mac) | Low (~2-10ms LAN) | High (WiFi on watch) | ✅ Yes (WiFi-only watch or cellular) | Medium |
| **Bluetooth via CoreBluetooth** | Medium (~50-200ms) | Low | ✅ Yes | High (custom protocol) |
| **Pass-through iPhone (WatchConnectivity + iPhone agent)** | Low (~5-15ms) | Low (BLE between watch/iPhone) | ❌ No (iPhone must be present) | Low-Medium |
| **Tailscale Mesh (Encrypted Overlay)** | Low+encryption overhead | Medium | ✅ Yes (if watch on same tailnet) | Low |

### Recommended Hybrid Strategy for ARES

Given Matthew's setup (Tailscale mesh, Ubiquiti LAN, iPhone usually present):

```
┌─────────────┐     BLE/WCSession      ┌─────────────┐     WiFi/LAN/Tailscale    ┌─────────────┐
│ Apple Watch │ ◄────────────────────► │   iPhone    │ ◄────────────────────────► │  Mac Studio │
│             │   (background aware)    │  ARES Agent │      WebSocket :7860      │  ARES Brain │
└─────────────┘                        └─────────────┘                           └─────────────┘
    ▲                                                                            ▲
    │                              Direct Path (WiFi)                             │
    │         (only when iPhone unavailable + watch on WiFi/Cellular)            │
    └──────────────────────────────────────────────────────────────────────────────┘
```

#### Implementation: Tiered Brain Adapter

```swift
protocol BrainTransport {
    func send(message: UserMessage) async throws -> AsyncStream<BrainResponse>
    var connectionState: ConnectionState { get }
}

@MainActor
class WatchBrainRouter: BrainTransport {
    private var iPhoneTransport: WatchConnectivityTransport?
    private var directTransport: WebSocketTransport?
    
    func send(message: UserMessage) async throws -> AsyncStream<BrainResponse> {
        // Priority 1: iPhone relay (low battery, always available if iPhone near)
        if WCSession.default.isReachable, let transport = iPhoneTransport {
            return try await transport.send(message: message)
        }
        
        // Priority 2: Direct WiFi to Mac Studio
        if NetworkPathMonitor().hasWiFi_or_Cellular, let transport = directTransport {
            return try await transport.send(message: message)
        }
        
        throw BrainError.noTransportAvailable
    }
}
```

#### WatchConnectivity Message Types

```swift
// WCSession message dictionary keys for ARES
enum WCMessageKey: String {
    case messageType       // "chat", "voice", "status", "sync"
    case payload           // JSON-encoded request
    case conversationID    // UUID of active thread
    case responseStream    // true if expecting streaming response
    case timestamp         // ISO8601
    case deviceID          // Unique sender device identifier
}
```

### Tailscale Considerations for Watch
- Apple Watch CAN run Tailscale via the iOS app configuration (if paired), but watch has no native Tailscale client
- Therefore: **iPhone relay is practically required for Tailscale-secured access** when off-LAN
- When watch is on home WiFi (same LAN as Mac Studio), direct IP connection works without Tailscale

---

## 4. Companion Mode Conventions: How Premium Apps Do It

### Case Study Analysis

#### Things 3 (Cultured Code)
- **Sync**: CloudKit private database + local Core Data
- **Watch App**: Standalone BUT syncs via iPhone when iPhone present, direct CloudKit when not
- **Complication**: Shows count of today's tasks via WidgetKit + CLKComplication
- **Convention**: Watch acts as "remote control" to iPhone/Mac database, not independent brain

#### Bear (Shiny Frog)
- **Sync**: CloudKit only (no custom server)
- **Watch App**: Note list + quick append via voice. Uses `WCSession` for instant append, CloudKit for full sync
- **Convention**: Watch optimized for capture, not heavy browsing/editing

#### CARROT Weather
- **Watch App**: Standalone weather engine + watch complication data source
- **Sync**: Purchases/settings via CloudKit, weather data direct API
- **Convention**: Watch gets its own API key for direct fetching; syncs "state" (prefs/locations) via CloudKit

#### Drafts (Agile Tortoise)
- **Watch App**: Capture-first. Voice → transcription → immediate sync to iCloud
- **Convention**: Watch is an INPUT device. Complex processing deferred to iPhone/Mac

### ARES Design Conventions to Follow

1. **Primary-Secondary Model**:
   - Mac Studio = Primary (brain, renderer, heavy compute)
   - iPhone = Secondary (always-present relay, camera/voice input)
   - Watch = Tertiary (capture-only, quick status, voice commands)

2. **UI Density Rules by Platform**:
   | Platform | Max messages visible | Input method | Avatar display |
   |----------|---------------------|--------------|----------------|
   | Mac Studio | 10-15 | Keyboard + Voice | Full Metal 3D |
   | iPad | 6-8 | Keyboard + Pencil + Voice | Metal/SpriteKit |
   | iPhone | 3-4 | Voice-first, keyboard | Simple animation |
   | Watch | 1 (current) | Voice-only | Text/status only |

3. **Complication & Live Activities**:
   - **Watch Complication**: Show Hermes connection status (green dot), unread count
   - **iPhone Live Activity**: When Mac is processing a long thought chain
   - **Dynamic Island**: Minimal — just "ARES thinking..." or notification

4. **Voice-First on Watch**:
   - Use `SFSpeechRecognizer` on watch for transcription
   - Stream audio to Mac for heavier STT if needed, OR use on-device recognition
   - Follow Bear/Drafts pattern: watch captures → phone/Mac processes → watch shows confirmation

5. **Cross-Device Handoff**:
   ```swift
   // NSUserActivity for conversation handoff
   let activity = NSUserActivity(activityType: "com.ares.conversation")
   activity.userInfo = ["conversationID": currentID.uuidString]
   activity.isEligibleForHandoff = true
   userActivity = activity
   ```

---

## 5. Cross-Device Sync: CloudKit vs Custom (NSync pattern)

### CloudKit + Core Data Stack (Recommended for ARES)

```swift
import CoreData
import CloudKit

class ConversationSyncManager {
    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "ARES_Conversations")
        
        // Private database for conversation history
        let privateStore = NSPersistentStoreDescription()
        privateStore.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.yourdomain.ares"
        )
        privateStore.cloudKitContainerOptions?.databaseScope = .private
        
        // Shared database for multi-user (future)
        // let sharedStore = NSPersistentStoreDescription()
        // sharedStore.cloudKitContainerOptions?.databaseScope = .shared
        
        container.persistentStoreDescriptions = [privateStore]
        container.loadPersistentStores { _, error in
            if let error = error { fatalError("Core Data load failed: \(error)") }
        }
        
        // Automatic sync
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
}
```

### The "NSync" Pattern (Named Sync Container)

This is likely a reference to **NSPersistentCloudKitContainer** + custom sync coordinator:

```swift
// Conversation model for sync
@Model  // SwiftData (iOS 17+) — recommended over Core Data for greenfield
class Conversation: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String?
    var createdAt: Date
    var lastModifiedAt: Date
    var messages: [Message]?
    var syncStatus: SyncStatus
    
    enum SyncStatus: String, Codable {
        case synced
        case pendingUpload
        case pendingDelete
        case conflict
    }
}

@Model
class Message {
    var id: UUID
    var role: String  // "user", "assistant", "system"
    var content: String
    var timestamp: Date
    var conversationID: UUID
    var tokenCount: Int?
}
```

### SwiftData + CloudKit (Modern Approach, iOS 17+/macOS 14+)

```swift
import SwiftData

@main
struct ARES_FaceApp: App {
    let modelContainer: ModelContainer
    
    init() {
        let schema = Schema([Conversation.self, Message.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic("iCloud.com.yourdomain.ares")
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not init SwiftData: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
```

**SwiftData advantages**:
- `@Query` automatic updates in SwiftUI
- Automatic CloudKit sync with `.automatic` configuration
- Platform-native: works identically on macOS/iOS/watchOS

### Event-Driven Sync for Real-Time Chat

CloudKit is NOT real-time enough for active chat sync. Use this hybrid:

```
Real-time layer:     WebSocket (per-device connection to Mac Studio)
                         │
Persistent layer:     Mac Studio persists to local DB ──► PostgreSQL/SQLite
                         │                                      │
Sync layer:            CloudKit/SwiftData ◄─────────────────────┘
                         │
All Devices:           Read from local SwiftData (CloudKit-backed),
                       Write via WebSocket to Mac Studio
```

**Why this works**:
- WebSocket = real-time message delivery
- CloudKit = offline availability + history bootstrap on new device
- Mac Studio = source of truth for AI state

### Device-Specific Sync Considerations

| Concern | Implementation |
|---------|----------------|
| Conflict resolution | Last-modified-wins at message level. Conversations use merge. |
| Sync frequency | SwiftData/CloudKit handles automatically. Custom throttle for large blobs. |
| Watch sync | Don't sync full history. Only last 50 messages + active conversation. |
| Large assets | Avatar models stay on Mac. Voice memos: iCloud Drive URLs, not DB blobs. |
| Network types | Disallow large syncs on cellular by default (Setting toggle). |

### Notification of Sync Events

```swift
// Listen for CloudKit sync to update UI reactively
NotificationCenter.default.addObserver(
    forName: NSPersistentCloudKitContainer.eventChangedNotification,
    object: container,
    queue: .main
) { notification in
    guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
        as? NSPersistentCloudKitContainer.Event else { return }
    
    switch event.type {
    case .import:
        print("Imported changes from cloud")
    case .export:
        print("Exported local changes to cloud")
    default: break
    }
}
```

---

## Recommended ARES Multi-Device Architecture Summary

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            ARES Ecosystem                                 │
├──────────────────────────────────────────────────────────────────────────┤
│  PRIMARY: Mac Studio (M1 Max)                                           │
│  - Ollama / Local LLM inference                                         │
│  - Hermes Agent (Discord, MCP orchestration)                            │
│  - ARES API server (:7860 WebSocket + REST)                            │
│  - Metal Avatar Renderer (macOS native)                                 │
│  - Source-of-truth SQLite/PostgreSQL                                    │
│  - CloudKit sync originator                                             │
├──────────────────────────────────────────────────────────────────────────┤
│  SECONDARY: iPhone / iPad                                               │
│  - ARES-Face app (SwiftUI, shared target)                               │
│  - WatchConnectivity host for watch relay                                │
│  - Camera/voice input routing to Mac                                    │
│  - SwiftData local cache (CloudKit synced)                                │
│  - Tailscale client for remote Mac access                               │
├──────────────────────────────────────────────────────────────────────────┤
│  TERTIARY: Apple Watch                                                   │
│  - Watch app (companion, voice-first)                                    │
│  - WCSession to iPhone for relay                                          │
│  - Direct WebSocket fallback (same WiFi only)                            │
│  - Complication: status + quick-launch                                    │
│  - SwiftData: last 50 messages only                                       │
├──────────────────────────────────────────────────────────────────────────┤
│  SYNC: CloudKit (private DB) + SwiftData                                  │
│  - Conversations, messages, settings sync across all devices               │
│  - Real-time: WebSocket to Mac Studio                                     │
│  - Offline: read from local SwiftData + sync on reconnect                 │
└──────────────────────────────────────────────────────────────────────────┘
```

### Immediate Next Steps

1. **Refactor ARES-Face** to multi-platform single target with `ARESKit` SPM package
2. **Create `WatchBrainRouter`** that prefers `WCSession` → iPhone → Mac Studio
3. **Add SwiftData models** for `Conversation` and `Message` with CloudKit container
4. **Implement WatchConnectivity** protocol with typed message envelopes
5. **Design voice-first Watch UI** (single-message view, no scrolling history)
6. **Register CloudKit container** at developer.apple.com (`iCloud.com.ares.system`)

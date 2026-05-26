// ARESIPCClient — Swift side of the ARES daemon IPC contract.
//
// Wire format: ZeroMQ DEALER connected to a Unix domain socket
// (default `ipc:///tmp/ares_ipc.sock`, override via ARES config).
// Every frame is a serialized `ares.ipc.Envelope` protobuf.
//
// See `ares/ipc/ares.proto` for the canonical schema. The Python side
// (`ares/ipc/zmq_server.py`) runs a ROUTER and dispatches Envelopes
// to handlers keyed on the oneof field.
//
// This file currently ships type-erased placeholder structs so call
// sites compile today. Wiring up the real client requires:
//
//   1. Add `.package(url: "https://github.com/apple/swift-protobuf",
//      from: "1.27.0")` to Package.swift.
//   2. Add a `.package(url: "https://github.com/zeromq/SwiftyZeroMQ5",
//      branch: "master")` (or another libzmq wrapper) — Apple does not
//      ship one.
//   3. Generate `ares.pb.swift` with
//      `protoc --swift_out=Sources/ARES/IPC ares/ipc/ares.proto`.
//   4. Replace the placeholder structs below with the generated types
//      and wire `ARESIPCClient` to a real DEALER socket.

import Foundation

public struct LogTrace: Sendable {
    public var level: String
    public var message: String
    public var timestamp: Int64
    public var module: String
}

public struct ApprovalRequest: Sendable {
    public var id: String
    public var description: String
    public var options: [String]
    public var timeoutSeconds: Int32
}

public struct ApprovalResponse: Sendable {
    public var id: String
    public var choice: String
}

public struct StateChange: Sendable {
    public var key: String
    public var value: String
    public var timestamp: Int64
}

public struct ConfigUpdate: Sendable {
    public var key: String
    public var value: String
}

public enum IPCPayload: Sendable {
    case logTrace(LogTrace)
    case approvalRequest(ApprovalRequest)
    case approvalResponse(ApprovalResponse)
    case stateChange(StateChange)
    case configUpdate(ConfigUpdate)
}

public struct Envelope: Sendable {
    public var payload: IPCPayload?
}

/// Stub IPC client. Construction succeeds; send/receive are not yet
/// wired (no libzmq dependency in Package.swift). Tracked in
/// the file header TODO list.
public final class ARESIPCClient {
    public let socketPath: String

    public init(socketPath: String = "/tmp/ares_ipc.sock") {
        self.socketPath = socketPath
    }

    public func send(_ envelope: Envelope) {
        // TODO: implement once SwiftyZeroMQ5 + swift-protobuf are wired
        // into Package.swift. See file header for steps.
        _ = envelope
    }
}

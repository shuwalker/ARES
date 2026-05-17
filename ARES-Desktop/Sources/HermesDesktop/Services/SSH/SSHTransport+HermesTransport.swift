import Foundation

/// SSHTransport conforms to HermesTransport.
///
/// Since SSHCommandResult and SSHTransportError are now typealiases
/// for TransportCommandResult and TransportError respectively, the
/// existing method signatures already satisfy the protocol requirements.
///
/// The only bridging needed is for validateSuccessfulExit, which the
/// protocol declares with TransportCommandResult (same type, so
/// no conversion is required).
extension SSHTransport: HermesTransport {}
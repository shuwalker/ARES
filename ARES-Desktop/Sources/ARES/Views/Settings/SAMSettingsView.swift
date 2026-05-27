import SwiftUI
import UserInterface
import APIFramework

/// Wraps SAM's PreferencesView for the ARES Settings tab.
/// PreferencesView requires EndpointManager as an environment object.
struct SAMSettingsView: View {
    @EnvironmentObject var samRuntime: SAMRuntime

    var body: some View {
        PreferencesView()
            .environmentObject(samRuntime.endpointManager)
    }
}

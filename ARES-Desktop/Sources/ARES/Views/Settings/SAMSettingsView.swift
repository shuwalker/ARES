import SwiftUI
import UserInterface
import APIFramework

/// Wraps SAM's PreferencesView for the ARES Settings tab.
/// PreferencesView requires EndpointManager as an environment object.
struct SAMSettingsView: View {
    @EnvironmentObject var samRuntime: SAMRuntime
    @AppStorage("alice_base_url") private var aliceBaseURL = ""
    @AppStorage("alice_api_key") private var aliceAPIKey = ""
    @AppStorage("ARES.hermesAPIKey") private var hermesAPIKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundStyle(ARESColors.textSecondary)
                                .frame(width: 120, alignment: .leading)
                            SecureField("paste Hermes API key", text: $hermesAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                        Text("Used by the Companion chat. Hermes returns 401 if this is empty. Relaunch ARES after changing.")
                            .font(.caption2)
                            .foregroundStyle(ARESColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                } label: {
                    Label("HERMES", systemImage: "bolt.horizontal.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(ARESColors.textSecondary)
                }
                .groupBoxStyle(SpartanGroupBoxStyle())

                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Endpoint")
                                .font(.subheadline)
                                .foregroundStyle(ARESColors.textSecondary)
                                .frame(width: 120, alignment: .leading)
                            TextField("http://localhost:8188", text: $aliceBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                        HStack {
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundStyle(ARESColors.textSecondary)
                                .frame(width: 120, alignment: .leading)
                            TextField("leave blank if not required", text: $aliceAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                        Text("Compatible with ComfyUI, AUTOMATIC1111, and any OpenAI-compatible image API.")
                            .font(.caption2)
                            .foregroundStyle(ARESColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                } label: {
                    Label("IMAGE GENERATION", systemImage: "paintbrush.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(ARESColors.textSecondary)
                }
                .groupBoxStyle(SpartanGroupBoxStyle())

                PreferencesView()
                    .environmentObject(samRuntime.endpointManager)
            }
            .padding(20)
        }
    }
}

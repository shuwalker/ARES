import SwiftUI
import ARESCore

struct ARESInspectorView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var isExtensionStorePresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Quick Controls")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 16)
                
                Divider()
                
                BackendPickerWidget()
                    .padding(.horizontal)
                
                Divider()
                
                VisionPickerWidget()
                    .padding(.horizontal)
                    
                Divider()
                
                VoicePickerWidget()
                    .padding(.horizontal)

                Divider()

                Button(action: {
                    isExtensionStorePresented = true
                }) {
                    HStack {
                        Image(systemName: "square.grid.3x3.fill.square")
                        Text("Pro Extensions")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)

                Spacer()
            }
        }
        .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
        .background(ARESColors.surface)
        .sheet(isPresented: $isExtensionStorePresented) {
            ExtensionStoreView()
                .frame(width: 600, height: 500)
        }
    }
}

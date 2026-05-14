import SwiftUI

struct FaceWindowView: View {
    @EnvironmentObject var daemon: ConsciousnessDaemon
    
    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
            
            FaceRenderer(state: daemon.state)
                .frame(width: 120, height: 120)
        }
        .clipShape(Circle())
    }
}

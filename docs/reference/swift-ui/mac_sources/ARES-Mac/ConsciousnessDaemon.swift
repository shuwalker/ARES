import Foundation
import Combine

class ConsciousnessDaemon: ObservableObject {
    @Published var state: FaceState = .idle
    
    private let backend = PythonBackend()
    private let checkpoint = CheckpointManager()
    private let calendar = CalendarBridge()
    private let logger = Logger()
    
    private var thoughtTimer: Timer?
    private var backendHealthTimer: Timer?
    
    init() {
        logger.info("Consciousness daemon starting")
        restoreCheckpoint()
        startThoughtLoop()
        startBackend()
    }
    
    // MARK: - Actions
    
    func awaken() {
        logger.info("Wake triggered")
        DispatchQueue.main.async {
            self.state = .awakened
        }
        checkpoint.update(state: "awakened")
        backend.wake()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.state = .listening
        }
    }
    
    func querySchedule() {
        logger.info("Schedule query")
        DispatchQueue.main.async {
            self.state = .thinking
        }
        
        let schedule = calendar.fetchTodaySchedule()
        let response = "Here's your schedule today:\n\(schedule)"
        
        DispatchQueue.main.async {
            self.state = .speaking
        }
        
        backend.think(text: "What is my schedule today?")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.returnToIdle()
        }
    }
    
    func shutdown() {
        logger.info("Daemon shutting down")
        thoughtTimer?.invalidate()
        backendHealthTimer?.invalidate()
        checkpoint.save(state: "sleeping")
        backend.idle()
    }
    
    // MARK: - Private
    
    private func startBackend() {
        backend.start()
        backendHealthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkBackendHealth()
        }
    }
    
    private func checkBackendHealth() {
        guard let cp = try? checkpoint.load() else {
            logger.warn("Backend health check failed, restarting")
            backend.restart()
            return
        }
        logger.debug("Backend healthy: \(cp)")
    }
    
    private func startThoughtLoop() {
        thoughtTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    private func tick() {
        guard state == .idle || state == .sleeping else { return }
        
        let thought: String
        switch state {
        case .idle:
            thought = "Idle at \(Date().formatted(date: .omitted, time: .shortened))"
        case .sleeping:
            thought = "System sleeping"
        default:
            thought = "State: \(state)"
        }
        
        logger.thought(thought)
        checkpoint.tick()
    }
    
    private func restoreCheckpoint() {
        if let cp = try? checkpoint.load() {
            state = cp == "sleeping" ? .sleeping : .idle
            logger.info("Restored checkpoint: \(cp)")
        }
    }
    
    private func returnToIdle() {
        state = .idle
        checkpoint.save(state: "idle")
        backend.idle()
    }
}
